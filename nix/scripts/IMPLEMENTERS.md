# nix/scripts — Implementers

A flake of roughly 80 bash/go utility scripts used across this repository,
grouped by prefix (e.g. `app-creator-*`, `argocd-*`, `context-*`,
`mono-flake-*`, `nixos-*`, `vault-*`, `agent-*`), plus a few standalone
tools such as `kommit` and `tg`.

See the [root IMPLEMENTERS.md](../../IMPLEMENTERS.md) for the repo-wide
convention and architecture overview.

## Overview

`flake.nix` auto-discovers every directory under `scripts/` and turns it
into a package, a shellcheck check, or interactive-shell glue, based on
which single file it contains. An unrecognized directory (none of
`go.mod`, `run.sh`, `lib.sh`, `source.sh`) makes flake evaluation `throw`
and breaks the *entire* flake, not just that one package.

## Directory layout

- `scripts/<name>/` — one directory per script/lib/function/Go package.
  Per-script `README.md` files are optional and uncommon; only a couple
  of scripts (e.g. `agent-stage`, `sync-cog-packages`) currently have
  one.

## How it works

- **Classification** (`flake.nix`'s `classify`): `go.mod` → Go package;
  else `run.sh` → shell script; else `lib.sh` → lib; else `source.sh` →
  source function.
- **`@lib:` inlining**: a `run.sh` may declare `# @lib: <lib-name>` lines
  (any position, parsed in file order). At build time, each declared
  lib's `lib.sh` is concatenated in declaration order *before* the
  `run.sh` text, then handed to `writeShellApplication`. This is **not
  transitive** — if lib A itself calls functions from lib B, every
  `run.sh` using A must *also* declare `# @lib: B` itself.
- **`./` rewrite**: if a script directory contains files besides its one
  classified file (e.g. this one has `run.sh` + `run.sh.tmpl`), every
  literal `./` substring in that dir's script text — including inside
  `../`, string literals, and comments — is rewritten to the directory's
  Nix store path before the package is built. This lets a `run.sh`
  reference a sibling file (e.g. a template) at a path that resolves
  correctly from the built package. It also means scripts in such
  directories must avoid any unintended `./` substring.
- **Outputs**: `packages.<name>` per script/lib-less package (plus `all`
  and `default`, a `symlinkJoin` of everything), `checks` (all packages,
  plus shellcheck of every `lib.sh` and `source.sh`), `devShells.<name>`
  (just that package) and `devShells.default` (every package plus `go`,
  `shellcheck`, `nix-update`), and `overlays.default` which exposes every
  package under `pkgs.ahilt-scripts.<name>`. `source.sh` functions are
  also concatenated (verbatim, no `@lib` support) into the top-level
  `interactiveShellInit` output.
- `x86_64-darwin` is excluded from `eachSystem`; scripts are expected to
  work on both Linux and macOS (the other darwin/linux systems).

## Making changes

### Adding a script, lib, or source function

Use the scaffolders (all require `PERSONAL_MONOREPO_LOCATION` to be set,
and all refuse to overwrite an existing directory):

```sh
nix run .#scripts-create-script -- --script-name my-script
nix run .#scripts-create-lib -- --lib-name my-lib
nix run .#scripts-create-source-function -- --source-function-name my-function
```

Each copies its template — see
[`scripts/scripts-create-script/run.sh.tmpl`](scripts/scripts-create-script/run.sh.tmpl),
[`scripts/scripts-create-lib/lib.sh.tmpl`](scripts/scripts-create-lib/lib.sh.tmpl),
[`scripts/scripts-create-source-function/source.sh.tmpl`](scripts/scripts-create-source-function/source.sh.tmpl)
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

- The `./` rewrite (see "How it works") applies to *every* `./`
  substring in a multi-file script directory's text, including inside
  `../`, strings, and comments — review generated/templated `run.sh`
  files for stray occurrences.
- `@lib` declarations are concatenated in declaration order with no
  transitive resolution — a lib that depends on another lib's functions
  needs every caller to declare both.
- `writeShellApplication` only shellchecks at build time; it does not
  declare runtime dependencies (`runtimeInputs`), so scripts currently
  rely on whatever happens to be on `PATH`. This is a known shortcoming
  — an area to improve, not something to copy going forward.
- A directory that doesn't match one of the four kinds breaks evaluation
  for the whole flake, not just that directory.
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
