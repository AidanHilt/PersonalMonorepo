# context-populate-context

Saves arbitrary `--kebab-case value` arguments as `UPPER_SNAKE_CASE`
variables into a context's `.env`, via `dotenvx set`.

## Usage

```sh
context-populate-context --name <context_name> --some-var value [--another-var value2 ...]
```

Every `--words-separated-by-dashes value` pair (other than `--name`) is
converted to `WORDS_SEPARATED_BY_DASHES=value` and written to
`$ATILS_CONTEXTS_DIRECTORY/<context_name>/.env`.

## Example

```sh
context-populate-context --name qa-cluster --vault-addr https://vault.qa.lan --kubeconfig-context kind-qa-cluster
# -> sets VAULT_ADDR and KUBECONFIG_CONTEXT in qa-cluster's .env
```

## What it does

- If `--name` is omitted, uses `$ATILS_CURRENT_CONTEXT` if set, otherwise
  prompts via `_context-context-selector`.
- Creates the context's `.env` if it doesn't already exist (does **not**
  create the rest of the context directory — see
  [context-create-context](../context-create-context/README.md)).
- Calls `dotenvx set <VAR> <value> -f <context>/.env` once per variable.
- If no `--<var>` arguments are given, prints a warning and exits
  successfully without changing anything.

## Prerequisites

- `ATILS_CONTEXTS_DIRECTORY` set.
- `dotenvx` on `PATH` (the script errors out if it isn't found).

## Caveats

- Variable flags must match `--word(-word)*` (letters/digits only per
  segment); anything else is rejected as an invalid argument format.
- Values are passed on the command line and written via `dotenvx set` —
  avoid putting highly sensitive values directly in shell history this way
  if that matters in your setup.
