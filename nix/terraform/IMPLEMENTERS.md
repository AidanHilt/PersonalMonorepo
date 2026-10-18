# nix/terraform — Implementers

Nix modules that generate Terraform (via terranix) for Authentik,
SeaweedFS, Vault, and Vault PKI. The generated modules are run by
[terragrunt/](../../terragrunt).

See the [root IMPLEMENTERS.md](../../IMPLEMENTERS.md) for the repo-wide
convention and architecture overview, [README.md](README.md) for the
"helm-linked terraform" concept and usage, and
[IMPROVEMENTS.md](IMPROVEMENTS.md) for known issues and cleanups not yet
scheduled.

## Overview

`flake.nix` discovers every directory under `modules/` that has an
`infra.nix` and builds it with `terranix.lib.terranixConfiguration` into a
`packages.aarch64-linux.<name>` Terraform-JSON derivation. Every `.nix` file
directly under `lib/` is imported and its returned attrset merged into a
single `libFunctions` attrset (via `//`), which is passed to every module
alongside `lib`, `inputs`, and `pkgs`. Modules read Helm chart values
(base + per-cluster overrides) from a pinned GitHub checkout of this same
repo via `lib/helm-value-loader.nix`, and emit Terraform resources gated by
a per-environment boolean variable, so a single build output can be
selectively applied per cluster with `-var <env>=true`.

## Directory layout

- `flake.nix` — discovers and builds one Terraform package per directory
  under `modules/` that has an `infra.nix`.
- `modules/<name>/infra.nix` — per-module Terraform generation. Current
  modules: `authentik`, `seaweedfs`, `vault`, `vault-pki`.
- `lib/` — shared helper code, merged into `libFunctions`:
  - `helm-value-loader.nix` — `loadMergedValues "<chart>"`: reads a Helm
    chart's base `values.yaml` and merges every cluster's
    `master-stack.yaml` over it.
  - `vault-secret-generator.nix` — `mkVaultSecret`/`mkVaultSecrets`: turns
    one `vault-config`-shaped entry (or a whole `loadMergedValues
    "vault-config"` result) into a Vault KV-v2 mount, policy, Kubernetes
    auth role, secret, and any generated `random_password`s/`tfVar`
    variables.
  - `vault-pki.nix` — `mkVaultPkiCertManager`/`mkPkiStackForEnv`: per
    hostname, a root CA, intermediate CA, and `cert-manager`
    role/policy/Kubernetes auth role.
  - `seaweedfs-object-generator.nix` — `mkSeaweedFsBucket`/
    `mkSeaweedFsUser`/`mkSeaweedFsStack`: a SeaweedFS bucket, an IAM user +
    policy + access key, and (via `mkSeaweedFsStack`, which combines the
    two and also creates the Vault secret for the resulting creds) a
    complete per-service SeaweedFS stack.
  - `authentik-resource-generator.nix` — `mkProxyApplication`: an Authentik
    proxy provider, application, and outpost for one `istio-ingress-config`
    entry.
  - `vault-provider.nix` — the `vault` Terraform provider block, plus (when
    `standalone = true`) the `vault_auth_backend.kubernetes` resource and
    its config (reads a pre-existing `vault-sa-token` secret); when
    `standalone = false`, a `data.vault_auth_backend.kubernetes` lookup
    instead.
  - `kubernetes-provider.nix` — the `kubernetes` Terraform provider block
    (`kubeconfig_location`/`kubeconfig_context` variables).

  `vault-provider.nix` and `kubernetes-provider.nix` are **not** meant to be
  called through `libFunctions` — every module imports them directly by
  path instead (see "Gotchas").

## How it works

- **Module discovery**: `flake.nix`'s `moduleNames` is every directory
  under `modules/` for which `modules/<name>/infra.nix` exists
  (`builtins.pathExists`). Each becomes
  `packages.aarch64-linux.<name>`, built via
  `terranix.lib.terranixConfiguration { modules = [ ./modules/<name>/infra.nix ]; extraArgs = { inherit libFunctions lib inputs pkgs; }; }`.
- **`libFunctions` merge**: `flake.nix` reads every `.nix` file directly
  under `lib/` (not recursively), imports each with
  `{ inherit lib pkgs inputs; }`, and folds the results together with `//`
  (last file wins on key collision — see "Gotchas").
- **Helm-linked values**: `lib/helm-value-loader.nix`'s `loadMergedValues`
  reads a chart's `values.yaml` from the `personalMonorepo` flake input
  (converted YAML→JSON via `yq-go` in a `runCommand` derivation, evaluated
  through import-from-derivation), then for every directory under
  `kubernetes/argocd/configuration-data/` in that same input, recursively
  merges that directory's `master-stack.yaml` (if present) over the base
  values with `lib.recursiveUpdate` (master-stack wins). The result is
  `{ <env> = merged; ...; original = <base values, unmerged>; }`.
- **Per-environment gating**: every generated resource that should only
  exist for a given environment sets `count = "${var.<env> ? 1 : 0}"` and
  the generator that creates it declares `variable.<env> = { type = "bool"; default = false; ...}`.
  Terragrunt (out of scope here) is what actually sets `<env> = true`, by
  setting the input named after its own cluster directory.
- **`original` is not uniformly filtered**. `vault-secret-generator.nix`'s
  `mkVaultSecrets` explicitly filters out the `original` key
  (`lib.filterAttrs (key: _: key != "original")`) before iterating, and the
  `seaweedfs` module (which also drives off `loadMergedValues
  "vault-config"`) follows that same convention. `authentik`'s and
  `vault-pki`'s generators do **not** filter it out — they iterate every key
  `loadMergedValues` returns, `original` included, and will declare an
  `original` boolean variable and emit (always-`count = 0`, since no
  terragrunt cluster directory is named `original`) resources for it. This
  looks unintentional (there's no sign `original` is meant to be a real,
  applyable environment) but is the current, accurate behavior — be aware
  of it rather than assuming it's filtered everywhere.
- **Standalone vs non-standalone**: `vault-provider.nix`'s `standalone`
  flag controls whether a module creates the Vault Kubernetes auth backend
  itself (`standalone = true`, used only by `modules/vault`) or reads an
  existing one via a `data` source (`standalone = false`, used by
  `vault-pki`, `authentik`, `seaweedfs`). `vault-secret-generator.nix`'s
  `mkVaultSecret` takes its own `standalone` option (defaulting to `true`)
  that controls whether its Kubernetes auth role `depends_on` the
  auth-backend resources `vault` module creates — pass this through
  consistently with the module's own `standalone`.

## Making changes

- **Adding/changing a module**: see [README.md](README.md)'s "Adding a new
  module" section for the mechanical steps. Remember: `libFunctions`
  functions only, providers by path, `lib.mkMerge` to combine, gate every
  resource with the environment `count`.
- **Adding/changing a `lib/` helper**: it becomes part of `libFunctions` for
  *every* module as soon as the file exists under `lib/` with a `.nix`
  suffix — there's no opt-in. Check its name doesn't collide with another
  `lib/` file's top-level keys (see "Gotchas").
- **Changing what a module reads from Helm values**: update the relevant
  chart's `values.yaml`/`master-stack.yaml` in this repo, **push the
  change**, then run `nix flake update personalMonorepo` here so the pinned
  input picks it up (see "Gotchas" — nothing here reads your working tree).
- **New files**: `git add` them. Nix flakes only see files tracked (or at
  least staged) by git; an untracked new `lib/*.nix` or `modules/*/infra.nix`
  silently won't be picked up.
- **Formatting/linting**: `nixfmt` (formatting) and `statix` (lint) run
  across this directory as part of `agent-validate --path nix/terraform`;
  keep both clean. There's no project-specific override beyond what those
  tools apply by default.

## Gotchas

- **`personalMonorepo` is a pinned GitHub ref, not your working tree.**
  `flake.nix`'s `inputs.personalMonorepo` points at
  `github:aidanhilt/PersonalMonorepo/project-rockhard/pki` with `flake =
  false`. Any change to `kubernetes/helm-charts/**/values.yaml` or
  `kubernetes/argocd/configuration-data/**` must be committed and pushed to
  that branch, then picked up here with `nix flake update personalMonorepo`
  (which updates `flake.lock`), before it affects what these modules
  generate. Expect that branch pin to change once the terragrunt work
  referenced in the branch name lands.
- **New files must be `git add`ed.** Flake evaluation only sees files known
  to git (tracked or staged); a brand-new `lib/*.nix` or
  `modules/<name>/infra.nix` that's only on disk won't be picked up by
  `builtins.readDir`-based discovery until it's added.
- **IFD needs an `aarch64-linux` builder.** `loadMergedValues` converts YAML
  to JSON via a `pkgs.runCommand` derivation evaluated through
  import-from-derivation, so *evaluating* these flakes — not just
  building — requires a working `aarch64-linux` Nix builder, regardless of
  the machine you're actually evaluating from.
- **`libFunctions` is a flat `//` merge of every `lib/*.nix` file**,
  including `vault-provider.nix` and `kubernetes-provider.nix` — so
  `libFunctions` ends up with junk top-level keys like `variable` and
  `provider` from those two files (their returned attrsets are Terraform
  resource fragments, not function collections), and a later `lib/` file
  reusing an existing key name (e.g. two files both exporting
  `mkFoo`) silently overwrites the earlier one with no warning. This is why
  `vault-provider.nix`/`kubernetes-provider.nix` are imported by path in
  every module instead of through `libFunctions`, and it's worth
  double-checking new `lib/` files don't shadow an existing export.
- **`vault` must apply before everything else.** It owns
  `resource.vault_auth_backend.kubernetes` (`standalone = true`); every
  other module reads that backend via
  `data.vault_auth_backend.kubernetes` (`standalone = false`), which will
  fail to resolve if `vault` hasn't been applied against that Vault
  instance yet.
- **Generated passwords live in Terraform state.** `random_password`
  resources created by `mkVaultSecret` for any `data.*` entry that isn't a
  literal, `{value}`, or `{tfVar}` have their plaintext result stored in
  Terraform state (and then written into the corresponding
  `vault_kv_secret_v2`) — treat the state file as sensitive accordingly.
- **Provider version pinning is inconsistent.** `authentik`
  (`goauthentik/authentik`, pinned `2026.2.0`) and `seaweedfs`
  (`JonasKop/seaweedfs`, pinned `0.2.0`) declare
  `terraform.required_providers`; `vault`, `kubernetes`, and `random` do
  not appear anywhere in this directory, so their provider versions are
  whatever Terraform/terragrunt resolves unpinned.
- **`vault` module needs a pre-existing `vault-sa-token` secret.**
  `vault-provider.nix`'s `standalone = true` path reads a Kubernetes secret
  named by `var.auth_secret_name` (default `vault-sa-token`) in
  `var.auth_secret_namespace` (default `vault`) to configure the Kubernetes
  auth backend — that secret must already exist in-cluster before `vault`
  is applied.
- **`seaweedfs` needs a running instance** reachable at `var.seaweedfs_endpoint`
  (default `http://localhost:8333`), with pre-existing admin
  `access_key`/`secret_key` supplied as `tfVar`s, plus a working
  `kubeconfig_*` for the Vault Kubernetes auth role bindings.
- **`authentik` needs a running Authentik instance** and a valid API token
  (`authentik_access_url`, `authentik_token`), since it manages live
  Authentik resources (providers/applications/outposts), not just
  Kubernetes/Vault objects.
- **The terragrunt `basename(dirname(get_terragrunt_dir())) = true` line is
  intentional, not a typo.** It's how an environment gets selected: the
  grandparent directory of a module's `terragrunt.hcl` (e.g.
  `qa-cluster/vault/terragrunt.hcl` → `qa-cluster`) names the Terraform
  variable that gets set to `true`, which must match a directory name under
  `kubernetes/argocd/configuration-data/`.
- **`mkVaultSecrets` filters `original`; `authentik`/`vault-pki` don't.**
  See "How it works" above — don't assume `original` is uniformly excluded
  across every generator; check the specific one you're touching.
- **`seaweedfs` and `vault` can both generate the same admin master
  secret — known, untested overlap.** The `seaweedfs` module was refactored
  to be helm-linked and has not been evaluated or tested since that
  refactor — treat this overlap as untested rather than confirmed-working
  or confirmed-broken, and re-check it during the full end-to-end test. See
  [IMPROVEMENTS.md](IMPROVEMENTS.md) for the details of the duplication.
