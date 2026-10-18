# context-activate-context

A sourced shell function (`source.sh`) that activates a context created by
[context-create-context](../context-create-context/README.md): exports its
variables into the current shell and points `tg`/Terragrunt at the
matching directory. See [../../../README.md](../../../README.md)'s "Kinds of
scripts" — not a standalone command; available via `interactiveShellInit`
or by sourcing `source.sh` yourself.

## Usage

```sh
context-activate-context --name <context_name>
context-activate-context -n <context_name>
context-activate-context            # prompts via _context-context-selector
```

## What it does

- Exports `ATILS_CURRENT_CONTEXT`, `ATILS_CURRENT_CONTEXT_DIR`
  (`$ATILS_CONTEXTS_DIRECTORY/<name>`), and
  `ATILS_CURRENT_CONTEXT_SCRIPTS_DIR` (`<context dir>/scripts`).
- Prepends the context's `scripts/` directory to `PATH`.
- Exports `TG_WORKING_DIR="$PERSONAL_MONOREPO_LOCATION/terragrunt/<name>"`
  — so the context name should match a
  [terragrunt/<cluster>](../../../../../terragrunt/README.md) directory name
  for `tg <module> ...` to work as documented there.
- If the context's `.env` exists and is non-empty, evaluates every
  variable from it (via `dotenvx get`) into the current shell — this is
  how `VAULT_ADDR`/`VAULT_TOKEN`/etc. set by
  [context-populate-context](../context-populate-context/README.md) or
  [vault-initialize](../../vault/vault-initialize/README.md) end up in your
  environment.
- If `KUBECONFIG_CONTEXT` ends up set (from the `.env`), runs
  `kubecm switch "$KUBECONFIG_CONTEXT" -s`.

## Prerequisites

- `ATILS_CONTEXTS_DIRECTORY` and `PERSONAL_MONOREPO_LOCATION` set in the
  environment.
- `dotenvx` on `PATH` if the context's `.env` has entries.
- `kubecm` on `PATH` if the context's `.env` sets `KUBECONFIG_CONTEXT`.

## Caveats

- An unknown flag or missing `--name`/`-n` value prints usage and exits
  non-zero (unknown flag) or falls through to the context selector
  (no `--name` given at all).
