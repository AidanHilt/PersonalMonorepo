# tg

A sourced shell function (`source.sh`) that wraps `terragrunt`, scoping it
to a working directory derived from `TG_WORKING_DIR`. See
[../../README.md](../../README.md)'s "Kinds of scripts" — this is not a
standalone command; it's available via `interactiveShellInit` (every
`source.sh` function sourced automatically), or by sourcing `source.sh`
yourself.

## Usage

```sh
tg                        # runs `terragrunt` in the current directory
tg <dir> [terragrunt args...]
```

If `TG_WORKING_DIR` is set and `$TG_WORKING_DIR/<dir>` exists as a
directory, `tg <dir> ...` runs:

```sh
terragrunt --working-dir "$TG_WORKING_DIR/<dir>" [terragrunt args...]
```

Otherwise it falls back to running `terragrunt "$@"` verbatim — so if
`TG_WORKING_DIR` is unset, or `<dir>` doesn't exist under it, `<dir>` is
passed straight through to `terragrunt` as its first argument instead of
being treated as a working-directory name.

## Example

```sh
tg vault plan
tg vault apply
```

## Prerequisites

- `terragrunt` on `PATH`.
- `TG_WORKING_DIR` set to get the `<dir>`-scoping behavior — normally set
  for you by `context-activate-context`, which points it at
  `terragrunt/<context-name>` in this repo. See
  [context-activate-context's README](../context-activate-context/README.md)
  and [terragrunt/README.md](../../../../terragrunt/README.md).
