# nix/scripts

A flake of shared bash and Go utility scripts, auto-discovered from
`scripts/<name>/`.

## Kinds of scripts

Each script directory is classified by the files it contains:

- **Shell script** (`run.sh`) — built as a standalone package with
  `writeShellApplication` (shellcheck-clean at build time).
- **Shell library** (`lib.sh`) — not packaged on its own; a script opts
  into it by declaring `# @lib: <name>`, and its contents get inlined
  into that script at build time.
- **Shell source function** (`source.sh`) — a shell function meant to be
  sourced into interactive shells (e.g. `cd`-like helpers), rather than
  run as a standalone command.
- **Go package** (`go.mod`) — built as a standalone package with
  `buildGoModule`.

## Using a script

Via the overlay, scripts are exposed under `pkgs.ahilt-scripts.<name>`
(e.g. `pkgs.ahilt-scripts.my-script`).

You can also work with a script directly from this flake:

```sh
nix build .#<name>      # build it
nix run .#<name> -- ... # run it
nix develop .#<name>    # a devShell with just that script on PATH
nix develop             # the default devShell, with every script on PATH
                         # plus go, shellcheck and nix-update
```

Source functions are also available via `interactiveShellInit`, for
shells that want every `source.sh` function sourced automatically.

Most scripts are self-contained and work anywhere the flake's shells are
used. Per-script documentation is optional: a script may have its own
`README.md` alongside its `run.sh`/`source.sh`/`go.mod`, and any script
that only works in a specific environment (e.g. the agent sandbox, a
NixOS host) documents that constraint in its own `README.md` — check
there before relying on a script outside the obvious context.

## Modifying scripts

See [IMPLEMENTERS.md](IMPLEMENTERS.md).
