# vault-provision

Applies the `vault` module (see
[terragrunt/README.md](../../../../../terragrunt/README.md)) under the
current `TG_WORKING_DIR`, non-interactively.

## Usage

```sh
vault-provision
```

Takes no arguments. Equivalent to:

```sh
terragrunt run apply --all --working-dir "$TG_WORKING_DIR/vault"
```

## Prerequisites

- `terragrunt` on `PATH`.
- `TG_WORKING_DIR` set, with a `vault/` subdirectory under it containing a
  valid `terragrunt.hcl` — normally set by
  [context-activate-context](../../context/context-activate-context/README.md) to
  `terragrunt/<context-name>`, so the active context's name must match a
  `terragrunt/<cluster>` directory that has a `vault/` module.
- Everything that module's `terragrunt.hcl` itself needs (e.g.
  `VAULT_ADDR`/`VAULT_TOKEN`, KeePass access for `run_cmd`-sourced
  secrets) — see [terragrunt/README.md](../../../../../terragrunt/README.md).

## Caveats

- The `vault` subdirectory name is hardcoded — this script only ever
  applies a module literally named `vault` under `$TG_WORKING_DIR`.
- If `TG_WORKING_DIR` is unset, the script prints an error message but
  does **not** exit there — it still reaches the `terragrunt run apply`
  line, where referencing the unset `$TG_WORKING_DIR` under the script's
  `set -euo pipefail` causes it to abort anyway. The net effect is still a
  non-zero exit, but via that unrelated mechanism rather than a clean,
  deliberate early return.
- Run this only after Vault itself is initialized and unsealed (see
  [vault-initialize](../vault-initialize/README.md) and
  [vault-unseal](../vault-unseal/README.md)) — `apply --all` doesn't wait
  for or check Vault's seal state.
