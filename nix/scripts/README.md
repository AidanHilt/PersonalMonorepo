# nix/scripts

A flake of shared bash and Go utility scripts, auto-discovered from
`scripts/<name>/` (a standalone script/lib/function) or
`scripts/<group>/<name>/` (a script/lib/function that's a member of a
prefix group, e.g. `scripts/vault/vault-initialize/`). Grouping is one
level deep only; shared libs that aren't a prefix match for any group
live in `scripts/libs/`.

## Kinds of scripts

Each script directory is classified by the files it contains:

- **Shell script** (`run.sh`) — built as a standalone package with
  `writeShellApplication` (shellcheck-clean at build time).
- **Shell library** (`lib.sh`) — not packaged on its own; a script opts
  into it with a whole-line `#include <name>` directive, and its
  contents get inlined into that script at build time. Includes are
  transitive: a lib may itself `#include` other libs, so a caller only
  needs to include what it calls directly.
- **Shell source function** (`source.sh`) — a shell function meant to be
  sourced into interactive shells (e.g. `cd`-like helpers), rather than
  run as a standalone command.
- **Go package** (`go.mod`) — built as a standalone package with
  `buildGoModule`.

## Using a script

Via the overlay, scripts are exposed under `pkgs.ahilt-scripts.<name>`
(e.g. `pkgs.ahilt-scripts.my-script`). Groups that contain at least one
runnable script are also exposed as a bundle, e.g.
`pkgs.ahilt-scripts.vault` (every `vault-*` script).

You can also work with a script directly from this flake:

```sh
nix build .#<name>      # build it
nix run .#<name> -- ... # run it
nix develop .#<name>    # a devShell with just that script on PATH
nix develop             # the default devShell, with every script on PATH
                         # plus go, shellcheck and nix-update
```

Groups work the same way for `build`/`develop`, e.g. `nix build .#vault`
or `nix develop .#vault` for a devShell with every `vault-*` script on
`PATH`. Group bundles are plain `symlinkJoin`s, not apps, so `nix run
.#<group>` does **not** work — use `nix shell .#<group>` or
`nix develop .#<group>` to get a group's scripts onto `PATH`.

Source functions are also available via `interactiveShellInit`, for
shells that want every `source.sh` function sourced automatically.

Most scripts are self-contained and work anywhere the flake's shells are
used. Per-script documentation is optional: a script may have its own
`README.md` alongside its `run.sh`/`source.sh`/`go.mod`, and any script
that only works in a specific environment (e.g. the agent sandbox, a
NixOS host) documents that constraint in its own `README.md` — check
there before relying on a script outside the obvious context.

## Runtime dependencies

A `run.sh`/`lib.sh` can declare a package it needs inline, right where
it's used, instead of relying on whatever happens to be on `PATH`:

```sh
: "${EXE_jq:=}" # runtime-dependency placeholder, substituted at build time
"${EXE_jq}" -r '.foo' <<<"$input"
some-tool --data-dir "${PKG_jq}/share/doc"
```

`${PKG_<name>}` expands to the package's store path, `${EXE_<name>}` to
its main executable; Nix resolves and substitutes these at flake-eval
time (so a missing package fails evaluation, not just at runtime) and
adds the referenced packages to the script's `runtimeInputs`. Every file
that uses a placeholder must declare it once, before first use, e.g.
`: "${EXE_jq:=}"` -- see [IMPLEMENTERS.md](IMPLEMENTERS.md)'s "Runtime
dependencies" section for why (shellcheck does not exempt `PKG_`/`EXE_`
from `SC2154` just for being uppercase) and for the full name-mapping
rules, the reserved `PKG_`/`EXE_` prefixes, and which script kinds
support it.

## Modifying scripts

See [IMPLEMENTERS.md](IMPLEMENTERS.md).
