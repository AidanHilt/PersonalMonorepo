# terragrunt — Improvements

Known issues and cleanups for this project, not yet scheduled. See
[IMPLEMENTERS.md](IMPLEMENTERS.md) for the mechanics these items refer to.

## `prod-cluster/vault` and `staging-cluster/vault` don't use the generated flow

Both `prod-cluster/vault/terragrunt.hcl` and
`staging-cluster/vault/terragrunt.hcl` set
`terraform { source = "../../../terraform/vault-config" }` instead of
including `root.hcl` — but `terraform/vault-config` doesn't exist anywhere
in the repository. Neither directory includes `root.hcl` or sets the
`basename(dirname(get_terragrunt_dir())) = true` environment flag that
the `nix/terraform` `vault` module relies on to gate its resources. As
written, `tg vault apply` (or `terragrunt apply`) in either directory would
fail to resolve a source.

## `staging-cluster/vault` points at the wrong cluster

`staging-cluster/vault/terragrunt.hcl` sets
`kubeconfig_context = "prod-cluster"` — applying it (once/if the missing
source above is fixed) would target the `prod-cluster` kubeconfig context
from a `staging-cluster` directory.

## `qa-cluster/authentik` has an empty Authentik token

`qa-cluster/authentik/terragrunt.hcl` sets `authentik_token = ""`. The
`authentik` module needs a valid API token to manage live Authentik
resources (see
[nix/terraform/IMPLEMENTERS.md](../nix/terraform/IMPLEMENTERS.md)'s
Gotchas) — an empty token will fail at apply time.

## `kind-kind` kubeconfig context hardcoded in `qa-cluster`

`qa-cluster/env.hcl` and `qa-cluster/authentik/terragrunt.hcl` /
`qa-cluster/vault-pki/terragrunt.hcl` / `qa-cluster/vault/terragrunt.hcl`
all hardcode `kubeconfig_context = "kind-kind"`, suggesting `qa-cluster` is
currently wired to a local `kind` cluster rather than a dedicated QA
environment.

## `qa-cluster` modules repeat inputs instead of merging `env.hcl`

`qa-cluster/env.hcl` declares shared `vault_url`, `vault_token`, and
`kubeconfig_context` inputs, but only `qa-cluster/seaweedfs/terragrunt.hcl`
actually reads and merges it
(`read_terragrunt_config(find_in_parent_folders("env.hcl"))` +
`merge(local.environment_vars.inputs, {...})`). `qa-cluster/vault`,
`qa-cluster/vault-pki`, and `qa-cluster/authentik` each repeat
`vault_url = get_env(...)`, `vault_token = get_env(...)`, and a literal
`kubeconfig_context` inline instead, so a shared-input change via
`env.hcl` only actually affects `seaweedfs`.

## `staging-cluster/vms` hardcodes an absolute, user-specific ISO path

`staging-cluster/vms/vms.hcl` sets
`iso_path = "/home/aidan/PersonalMonorepo/result/iso-image-x86_64/iso/atils-nixos-bootstrap-x86_64.iso"`
— an absolute path tied to one user's home directory and one checkout
location, which won't resolve on another machine or checkout.

## Empty/blank `env.hcl` files

`prod-cluster/env.hcl` is present but its `inputs = {}` block is empty, and
`staging-cluster/env.hcl` is an entirely blank file (no `inputs` block at
all). Neither cluster currently has any shared inputs wired through
`env.hcl` (and, per the item above, nothing in `prod-cluster` or
`staging-cluster` reads `env.hcl` at all today).

## `vault-provision` doesn't actually stop cleanly when `TG_WORKING_DIR` is unset

`nix/scripts/scripts/vault-provision/run.sh` checks `[[ -v TG_WORKING_DIR ]]`
and calls `print_error 'Please set TG_WORKING_DIR'` if it's unset, but
`print_error` only echoes a message — it doesn't call `exit`. The script
then unconditionally reaches
`terragrunt run apply --all --working-dir "$TG_WORKING_DIR/vault"`; under
the script's `set -euo pipefail`, referencing the unset `$TG_WORKING_DIR`
there triggers bash's "unbound variable" behavior and the script exits
non-zero anyway — but via that unrelated mechanism, not a deliberate
early return, and after already starting (and misleadingly implying it
might continue). The `vault` subdirectory name is also hardcoded in that
line, so `vault-provision` can only ever apply a module literally named
`vault` under `$TG_WORKING_DIR`.

## Mixed old/new Terragrunt CLI styles

`root.hcl`'s `generate` block and every `run_cmd(...)` call for secrets
(e.g. `run_cmd("--terragrunt-quiet", "keepass-retrieve-secret", ...)`) use
the older `run_cmd(["--terragrunt-...flag"], ...)` / global-flag style,
while `vault-provision` invokes Terragrunt with the newer
`terragrunt run apply --all --working-dir ...` subcommand style. Both are
present and in active use in this repository; this is noted as an
inconsistency to be aware of (e.g. when checking which CLI flags/version a
change needs to support), not something confirmed broken.

## No remote state backend

No `remote_state` block is configured anywhere in `terragrunt/`, so every
module's Terraform state is local only (see
[IMPLEMENTERS.md](IMPLEMENTERS.md)) — state isn't shared between machines,
isn't backed up, and two people/checkouts applying the same module would
each have their own, divergent state.

## No documented required-environment-variable list per module

Each module `terragrunt.hcl`'s `get_env(...)` calls are the only place that
lists which environment variables it needs; there's no single place (here
or in the context system) that enumerates, per module, which variables
must be set before `tg <module> apply` will parse successfully.

## `root.hcl` hardcodes `aarch64-linux` and a fixed relative depth

`root.hcl`'s `generate` block hardcodes both the target system
(`nix/terraform/#packages.aarch64-linux.<name>`) and the `../../../`
relative path to `nix/terraform` — a module directory built for a
different architecture, or placed at a different depth than
`terragrunt/<cluster>/<module>/`, isn't supported without editing
`root.hcl` itself.

## `nix/terraform`'s `personalMonorepo` pin

Out of scope to change here, but worth tracking: `nix/terraform`'s
`personalMonorepo` flake input is pinned to a branch named for this
terragrunt work (`project-rockhard/pki`) — see
[nix/terraform/IMPLEMENTERS.md](../nix/terraform/IMPLEMENTERS.md)'s
Gotchas and [nix/terraform/IMPROVEMENTS.md](../nix/terraform/IMPROVEMENTS.md).
That pin is expected to need to change once the terragrunt-side work
referenced by the branch name lands.
