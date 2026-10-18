# vault-unseal

Unseals Vault at `$VAULT_ADDR` using `VAULT_UNSEAL_KEY_1` and
`VAULT_UNSEAL_KEY_2` (as saved by
[vault-initialize](../vault-initialize/README.md)).

## Usage

```sh
vault-unseal
```

Takes no arguments.

## What it does

1. Checks `vault status -format=json`; exits if Vault is already unsealed,
   or if status can't be fetched (e.g. Vault unreachable at `$VAULT_ADDR`).
2. Runs `vault operator unseal "$VAULT_UNSEAL_KEY_1"`.
3. If still sealed, runs `vault operator unseal "$VAULT_UNSEAL_KEY_2"`.
4. If still sealed after both keys (this instance was initialized with a
   higher threshold, or a key is wrong), prints the current `vault status`
   and exits non-zero — it does not try any further
   `VAULT_UNSEAL_KEY_*` variables.

## Prerequisites

- `vault` and `jq` on `PATH`.
- `VAULT_ADDR` pointed at the sealed Vault instance.
- `VAULT_UNSEAL_KEY_1` and `VAULT_UNSEAL_KEY_2` set (normally via an
  activated context — see
  [context-activate-context](../../context/context-activate-context/README.md)).

## Caveats

- Only ever tries keys 1 and 2, matching `vault-initialize`'s
  2-of-3 threshold default — if Vault was initialized with a different
  `-key-threshold`/`-key-shares`, this script won't use any additional
  keys beyond the first two automatically.
