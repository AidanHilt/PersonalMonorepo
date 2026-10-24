# nix/terraform — Improvements

Known issues and cleanups for this project, not yet scheduled. See
[IMPLEMENTERS.md](IMPLEMENTERS.md) for the architecture these items refer
to.

## SeaweedFS / Vault overlap

- **`seaweedfs` and `vault` can both generate the same admin master
  secret.** `modules/vault/infra.nix` calls `mkVaultSecrets` over every
  enabled `vault-config` entry, including `seaweedfs` whenever it's
  `enabled: true`; `modules/seaweedfs/infra.nix` separately calls
  `mkVaultSecret "seaweedfs" { ... }` itself for the same entry. Both
  resolve to the same `seaweedfs-<env>` KV-v2 mount/secret (key
  `seaweedfs`, no `mount` override in either call). Applying both states
  for an environment where `seaweedfs.enabled` is `true` may conflict. The
  `seaweedfs` module was refactored to be helm-linked and has not been
  evaluated or tested since that refactor — this overlap should be
  re-checked during the full end-to-end test, not assumed broken or
  working.
- **`modules/seaweedfs`'s `provider.seaweedfs` always references
  `var.access_key`/`var.secret_key`, but those variables are only declared
  when some environment has `seaweedfs.enabled: true`.** `mkMasterSecret`
  (in `modules/seaweedfs/infra.nix`) only calls `mkVaultSecret`, which is
  what declares the `access_key`/`secret_key` `tfVar` variables, inside its
  `if (envValues.seaweedfs.enabled or false)` branch; if no configured
  environment enables `seaweedfs`, `mkMasterSecret` returns `{ }` for every
  environment and those variables are never declared, while the static
  `provider.seaweedfs` block unconditionally references them.
- **Each seaweedfs stack and the master secret both define an identical
  `vault_mount."seaweedfs-<env>"`.** Both call sites resolve `mountName` to
  the literal `seaweedfs` (neither call passes a `mount` override), so
  every `mkVaultSecret "seaweedfs" { ... }` call — one from the master
  secret in `modules/seaweedfs`, one per enabled `vault-config` entry from
  `mkVaultSecrets` in `modules/vault` — emits the same
  `vault_mount."seaweedfs-<env>"` resource. Whether these merge cleanly
  under terranix (same module, different modules) is unconfirmed; this is
  the same underlying duplication as the overlap above, not a separate
  issue.

## `original` key filtering is inconsistent

`loadMergedValues` (`lib/helm-value-loader.nix`) returns `{ <env> =
merged; ...; original = base; }`. `mkVaultSecrets`
(`lib/vault-secret-generator.nix`) and the `seaweedfs` module
(`modules/seaweedfs/infra.nix`, via its own `lib.filterAttrs (envName: _:
envName != "original")`) both filter out `original` before iterating.
`vault-pki` (`lib/vault-pki.nix`'s `mkPkiStackForEnv`) and `authentik`
(`modules/authentik/infra.nix`) do not — they iterate every key
`loadMergedValues` returns, `original` included, declaring an `original`
boolean Terraform variable and emitting resources gated with
`count = "${var.original ? 1 : 0}"` that can never actually apply (no
terragrunt cluster directory is named `original`). Harmless as currently
used, but confusing and inconsistent; either filter uniformly or document
why `vault-pki`/`authentik` don't need to.

## Provider pinning

`terraform.required_providers` is declared for `authentik`
(`goauthentik/authentik`, pinned `2026.2.0`) and `seaweedfs`
(`JonasKop/seaweedfs`, pinned `0.2.0`), but not for `vault`, `kubernetes`,
or `random` anywhere in this directory — those resolve to whatever
Terraform/terragrunt picks unpinned.

## `personalMonorepo` pin

`flake.nix`'s `personalMonorepo` input is pinned to
`github:aidanhilt/PersonalMonorepo/project-rockhard/pki` (`flake = false`).
This branch name references in-flight terragrunt work; expect the pin to
need to change (to a different branch, or off a branch entirely) once that
work lands.

## `libFunctions` flat merge

`flake.nix` builds `libFunctions` by folding every `lib/*.nix` file's
returned attrset together with `//` (last file wins on key collision), with
no filtering. This includes `vault-provider.nix` and
`kubernetes-provider.nix`, whose returned attrsets are Terraform resource
fragments (`variable`, `provider`, `resource`, `data`), not function
collections — so `libFunctions` ends up with unused junk top-level keys
from those two files, and nothing guards against a later `lib/` file
silently overwriting an earlier file's same-named export.

## IFD requires an aarch64-linux builder

`lib/helm-value-loader.nix` converts a chart's `values.yaml` from YAML to
JSON via a `pkgs.runCommand` derivation evaluated through
import-from-derivation, so *evaluating* any of these flakes (not just
building) requires a working `aarch64-linux` Nix builder, regardless of the
machine doing the evaluating.

## `vault-pki` hardcoded defaults aren't Helm-configurable

`mkVaultPkiCertManager` (`lib/vault-pki.nix`) defaults `vaultAddr` to
`http://vault.${hostname}` and hardcodes `rootTtl`/`intTtl`/`roleMaxTtl`
defaults, but `mkPkiStackForEnv` only ever passes through `hostname` and
`environment` from the merged Helm values — `istio-ingress-config`'s
`hostnames` list drives which hostnames get a CA pair, but none of
`vaultAddr`, `rootTtl`, `intTtl`, or `roleMaxTtl` can currently be
overridden via Helm values.

## Noisy reformat commit (informational)

A prior commit bundled a `nixfmt` reformat of files untouched by that
commit's actual logic change (`authentik-resource-generator.nix`,
`helm-value-loader.nix`, the provider files, `infra.nix` files) together
with the logic change itself, making the diff/history for that change
harder to review. Not something to fix retroactively — noted so future
changes keep formatting-only and logic commits separate where practical.
