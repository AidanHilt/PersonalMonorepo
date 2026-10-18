# context-create-context

Creates a new context directory: an empty `.env` plus an empty `scripts/`
subdirectory under `$ATILS_CONTEXTS_DIRECTORY`.

## Usage

```sh
context-create-context --name <context_name>
context-create-context -n <context_name>
context-create-context               # prompts for a name interactively
```

## What it does

- Validates the name (letters, numbers, `-`, `_` only; non-empty).
- Fails with an error if `$ATILS_CONTEXTS_DIRECTORY/<name>` already exists.
- Otherwise creates `$ATILS_CONTEXTS_DIRECTORY/<name>/.env` (empty) and
  `$ATILS_CONTEXTS_DIRECTORY/<name>/scripts/` (empty directory).

## Prerequisites

- `ATILS_CONTEXTS_DIRECTORY` set in the environment (the script errors out
  immediately if it isn't).

## Notes

- This only creates the directory structure — use
  [context-populate-context](../context-populate-context/README.md) to set
  variables in the new `.env`, and
  [context-activate-context](../context-activate-context/README.md) to
  activate it.
- For [terragrunt/](../../../../terragrunt/README.md) usage, name the
  context the same as the `terragrunt/<cluster>` directory you intend to
  operate on — `context-activate-context` derives `TG_WORKING_DIR` from
  the context name.
