# vault-initialize

Runs `vault operator init` against the Vault instance at `$VAULT_ADDR` and,
if a context is active, saves the resulting unseal keys and root token
into that context's `.env`.

## Usage

```sh
vault-initialize
```

Takes no arguments.

## What it does

- Runs `vault operator init -key-shares=3 -key-threshold=2 -format=json`
  (fails with an error if Vault is already initialized or the call
  otherwise fails).
- If `$ATILS_CURRENT_CONTEXT` is set (see
  [context-activate-context](../../context/context-activate-context/README.md)):
  - Saves each unseal key as `VAULT_UNSEAL_KEY_1`, `VAULT_UNSEAL_KEY_2`,
    `VAULT_UNSEAL_KEY_3`, and the root token as `VAULT_TOKEN`, into
    `$ATILS_CONTEXTS_DIRECTORY/$ATILS_CURRENT_CONTEXT/.env` via
    `dotenvx set`.
  - This is a 3-share, 2-threshold init — only two of the three
    `VAULT_UNSEAL_KEY_*` values are needed to unseal (see
    [vault-unseal](../vault-unseal/README.md), which only uses keys 1
    and 2).
- If no context is active, prints the raw `vault operator init` JSON
  output to stdout instead of saving anything — you're responsible for
  capturing the unseal keys and root token yourself in that case.

## Prerequisites

- `vault`, `jq`, and `dotenvx` on `PATH`.
- `VAULT_ADDR` pointed at an un-initialized Vault instance.
- A context active (`context-activate-context`) if you want the keys/token
  saved automatically.

## Caveats

- Running this against an already-initialized Vault fails outright — it
  does not re-fetch or rotate keys.
- The unseal keys and root token this writes are highly sensitive —
  they're written into the context's `.env` via `dotenvx set`; treat that
  file accordingly.
