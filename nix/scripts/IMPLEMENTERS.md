# nix/scripts — Implementers

A flake of roughly 90 bash/go utility scripts used across this repository,
mostly organized into prefix groups (e.g. `app-creator/`, `argocd/`,
`context/`, `helm/`, `mono-flake/`, `nixos/`, `scripts/`, `system-tasks/`,
`vault/`, `agent/`), plus shared libs under `libs/` and a handful of
standalone top-level tools (e.g. `kommit`, `tg`, `pkg-install`).

See the [root IMPLEMENTERS.md](../../IMPLEMENTERS.md) for the repo-wide
convention and architecture overview.

## Overview

`flake.nix` auto-discovers every directory under `scripts/` (one level of
grouping at most) and turns each leaf into a package, a shellcheck check,
or interactive-shell glue, based on which single file it contains. An
unrecognized directory (none of `go.mod`, `run.sh`, `lib.sh`,
`source.sh`, and not itself a group of such directories) makes flake
evaluation `throw`, naming the offending path, and breaks the *entire*
flake, not just that one package. Nested groups (a group inside a group)
are not supported and also throw.

Every name — script, Go package, lib, source function, and group — must
be globally unique across all of `scripts/`, regardless of nesting; a
name collision (e.g. a lib named the same as a group) throws, naming
both colliding paths.

## Directory layout

- `scripts/<name>/` — a standalone script/lib/function/Go package at the
  top level.
- `scripts/<group>/<name>/` — a script/lib/function/Go package that is a
  member of `<group>`. A directory counts as a group when it contains no
  marker file itself, only further script/lib/function/Go-package
  directories; grouping is one level deep only. Names are always the
  leaf directory name, never prefixed by the group (e.g. the lib at
  `scripts/agent/agent-plan-classify/` is addressed as
  `agent-plan-classify`, not `agent/agent-plan-classify`).
- **Placement convention**: a script or lib belongs in a group only when
  its name actually starts with that group's prefix (e.g.
  `vault-initialize` belongs in `vault/` because it's prefixed
  `vault-`). Libs that aren't a prefix match for any group — i.e. most
  shared/general-purpose libs — live in `scripts/libs/` instead (e.g.
  `args-and-help`, `printing-and-output`, `env-checks`). Never place a
  lib by who happens to use it; place it by whether its own name shares
  a group's prefix.
- Per-script `README.md` files are optional and uncommon; only a couple
  of scripts (e.g. `agent-stage`, `sync-cog-packages`) currently have
  one.

## How it works

- **Classification** (`flake.nix`'s `classifyDir`): `go.mod` → Go
  package; else `run.sh` → shell script; else `lib.sh` → lib; else
  `source.sh` → source function; else (no marker file) → group, whose
  immediate children are classified the same way (one level only — a
  group's child that is itself a group throws).
- **Groups**: a group with at least one runnable script (`run.sh` or
  `go.mod`) member gets a `packages.<group>` bundle (a `symlinkJoin` of
  just that group's packages), plus `devShells.<group>` and
  `overlays.default`'s `ahilt-scripts.<group>`. A group made up only of
  libs and/or source functions (e.g. `libs/`) emits no bundle/devShell/
  overlay entry — there's nothing runnable to bundle. Group bundles are
  excluded from `checks` (only individual packages, and lib/source
  shellcheck checks, run there) and from the overlay's `all`.
  `nix run` does **not** work on a group (a `symlinkJoin` isn't an
  app) — use `nix shell .#<group>` or `nix develop .#<group>` instead.
  Libs are addressed globally by directory name via `# @lib:`,
  regardless of which group (if any) they live in.
- **Flake outputs recap**: `packages.<name>` per script/lib-less package
  (leaf) plus `packages.<group>` per group with packages, plus `all`
  (every leaf, no groups) and `default` (= `all`); `checks` (every leaf
  package, plus shellcheck of every `lib.sh` and `source.sh` — group
  bundles excluded); `devShells.<name>` and `devShells.<group>` (that
  one package, or that group's packages) plus `devShells.default`
  (every leaf package plus `go`, `shellcheck`, `nix-update`); and
  `overlays.default`, which exposes every leaf package and every group
  bundle under `pkgs.ahilt-scripts.<name>` / `pkgs.ahilt-scripts.<group>`
  (deliberately excluding `all`, which stays a packaging convenience
  only, not part of the global package set). `source.sh` functions are
  also concatenated (verbatim, no `@lib` support) into the top-level
  `interactiveShellInit` output, regardless of grouping.
- **`@lib:` inlining**: a `run.sh` may declare `# @lib: <lib-name>` lines
  (any position, parsed in file order). At build time, each declared
  lib's `lib.sh` is concatenated in declaration order *before* the
  `run.sh` text, then handed to `writeShellApplication`. This is **not
  transitive** — if lib A itself calls functions from lib B, every
  `run.sh` using A must *also* declare `# @lib: B` itself.
- **`./` rewrite** (`rewriteLocalPaths`): if a script directory contains
  files besides its one classified file (e.g. this one has `run.sh` +
  `run.sh.tmpl`), that dir's script text is rewritten so every `./`
  that starts a path token becomes the directory's Nix store path
  before the package is built — specifically, every occurrence of
  `./` immediately preceded by a newline, space, tab, `"`, `'`, `(`, or
  `=` (i.e. the start of a path-looking token), not a bare
  string-replace of every `./` substring. This lets a `run.sh`
  reference a sibling file (e.g. a template) at a path that resolves
  correctly from the built package, while leaving `../foo` (which
  contains `./` but not as a token start) untouched. It also means
  scripts in such directories must avoid any unintended `./` occurring
  right after one of those characters.
- `x86_64-darwin` is excluded from `eachSystem`; scripts are expected to
  work on both Linux and macOS (the other darwin/linux systems).

## Making changes

### Adding a script, lib, or source function

Use the scaffolders (all require `PERSONAL_MONOREPO_LOCATION` to be set,
and all refuse a name that already exists anywhere under `scripts/` —
as a top-level entry, as a member of any group, or as a group name
itself):

```sh
nix run .#scripts-create-script -- --script-name my-script
nix run .#scripts-create-lib -- --lib-name my-lib
nix run .#scripts-create-source-function -- --source-function-name my-function
```

All three also take an optional `--group <name>`, which creates
`scripts/<group>/<name>` instead of a top-level `scripts/<name>`
(creating the group directory if it doesn't exist yet) and validates
`<group>` as lowercase-kebab-case:

```sh
nix run .#scripts-create-script -- --script-name my-script --group my-group
```

Only use `--group` when the new name actually starts with that group's
prefix (see the placement convention in "Directory layout" above) — a
lib that doesn't match any group's prefix belongs in `scripts/libs/`
instead, which today means running `scripts-create-lib` *without*
`--group` and then `git mv`-ing the result into `scripts/libs/`
yourself (there's no `--libs`-shortcut flag).

Each copies its template — see
[`scripts/scripts/scripts-create-script/run.sh.tmpl`](scripts/scripts/scripts-create-script/run.sh.tmpl),
[`scripts/scripts/scripts-create-lib/lib.sh.tmpl`](scripts/scripts/scripts-create-lib/lib.sh.tmpl),
[`scripts/scripts/scripts-create-source-function/source.sh.tmpl`](scripts/scripts/scripts-create-source-function/source.sh.tmpl)
— into the new directory, substituting the given name. Names are
validated as lowercase-kebab-case, optionally with a single leading
underscore for internal-only scripts (see "Naming conventions" below).

The canonical `run.sh` skeleton (what `scripts-create-script` scaffolds)
declares `# @lib: printing-and-output` and `# @lib: args-and-help`, and
starts with `args_description`/`args_example`/`args_parse`; add
`# @lib: env-checks` and `require_env`/`require_monorepo` calls if the
script needs environment variables. There is currently no scaffolder for
Go scripts (see "Go scripts" below).

### Naming conventions

Scripts are grouped by a shared prefix (e.g. `context-*`, `vault-*`)
chosen as the first/simplest concept a user would reach for, so
tab-completion on that prefix reliably recalls the exact script name. A
leading underscore (`_name`) marks a script as internal-only — a helper
meant to be used by other scripts/libs, not invoked directly by a user.
The shared prefix is also, by convention, the name of the `scripts/`
group directory the script lives in (see the placement convention under
"Directory layout") — but the group is just a directory grouping for
flake outputs, independent of the `@lib`/naming-prefix convention
itself.

### `source.sh` rules

- Function name must match the directory name exactly.
- Use `return`, never `exit` — these run in the user's interactive shell.
- No `set -e` / `set -u` / `set -o pipefail` — they'd leak into the
  caller's shell.
- Declare variables `local`.
- No `@lib` support: the file is concatenated verbatim into
  `interactiveShellInit`, so it cannot call lib functions.

### Lib rules

- Functions only — never call `exit` (or anything with side effects) at
  top level, since the file is inlined into every consumer.
- Mark every function `#shellcheck disable=SC2329` (shellcheck can't see
  that it's called from the `run.sh` it gets concatenated into).
- `@lib` is not transitive — if your lib calls another lib's functions,
  document that callers must declare both.
- Changing a lib affects every script that declares it; check for
  callers before changing its behavior or signature.

### Go scripts

No scaffolder yet — set up manually: `go.mod`, `main.go`, and (if there
are external dependencies, i.e. a `go.sum`) a `vendor-hash.nix` file
exporting the `vendorHash` string. `version = "0.1.0"` in `flake.nix` is
a hardcoded placeholder with no cocogitto/release meaning. If there's no
`go.sum` (stdlib-only), `vendorHash` is `null` and no `vendor-hash.nix`
is needed. When deps change, update the hash with `nix-update
<name>`, or by setting `vendorHash` in `vendor-hash.nix` to
`lib.fakeHash`, running a build, and copying the `got:` hash it reports.

### Formatting / linting

- Shell: `shfmt -i 2` (2-space indent), `shellcheck`.
- Go: `gofmt`, `go vet`.
- Useful commands while iterating (none mandatory, pick what fits):
  `nix build .#<name>`, `nix run .#<name>`, `nix flake check`,
  `nix develop`, or rebuilding a consuming system. `agent-validate` is
  specific to the agent dispatch workflow, not a general-purpose check.

## Gotchas

- The `./` rewrite (see "How it works") only rewrites `./` where it
  starts a path token (after whitespace, a quote, `(`, or `=`) — but
  that's still a textual pattern match, not a real path parse, so
  review generated/templated `run.sh` files for a stray `./` right
  after one of those characters that wasn't meant to be a path.
- `@lib` declarations are concatenated in declaration order with no
  transitive resolution — a lib that depends on another lib's functions
  needs every caller to declare both.
- `nix run .#<group>` does not work — group bundles are `symlinkJoin`s,
  not apps; use `nix shell .#<group>` or `nix develop .#<group>`
  instead. `nix run .#<name>` still works for individual scripts.
- `writeShellApplication` only shellchecks at build time; it does not
  declare runtime dependencies (`runtimeInputs`), so scripts currently
  rely on whatever happens to be on `PATH`. This is a known shortcoming
  — an area to improve, not something to copy going forward.
- A directory that doesn't match one of the four kinds (and isn't a
  group of such directories) breaks evaluation for the whole flake, not
  just that directory; the error names the offending path. Nested
  groups throw the same way — grouping is one level deep only.
- Every script/lib/source-function/group name must be unique across all
  of `scripts/`, not just within its own kind or its own group — a
  clash throws, naming both colliding paths.
- `vendor-hash.nix` must be updated whenever a Go script's dependencies
  change, or its build will fail with a hash mismatch.
- The Go `version = "0.1.0"` in `flake.nix` is a placeholder; it has no
  release/versioning meaning.
- `x86_64-darwin` is excluded from the flake's systems; scripts should
  still be written to work on both Linux and macOS (the other darwin
  variant).
- Scripts that only work in a specific environment (e.g. the agent
  sandbox, NixOS hosts) should document that constraint in their own
  `README.md`.
- Known `source.sh` files that don't follow the rules above:
  `context-cd` and `context-activate-context` call `exit` instead of
  `return` (and `context-activate-context`'s function isn't namespaced
  to match its directory name). Bringing them into compliance is out of
  scope here but should be done as part of any future work that touches
  either file. More generally, existing scripts may predate current
  conventions — bring a script into compliance when you're already
  touching it, rather than as a drive-by change.
