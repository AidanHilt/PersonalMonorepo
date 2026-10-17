# nix/terraform

Nix modules that generate Terraform (as JSON, via [terranix](https://terranix.org/))
for Authentik, SeaweedFS, Vault, and Vault PKI. The generated modules are run
by [terragrunt/](../../terragrunt) (not covered here — see that directory's
own docs, which are still forthcoming).

## Overview

Each directory under `modules/` with an `infra.nix` becomes one buildable
Terraform package: `modules/vault`, `modules/vault-pki`, `modules/authentik`,
`modules/seaweedfs`. `lib/` holds the shared Nix helpers each module is built
from — value loading, per-service Vault secret/mount generation, Vault PKI
cert-manager stacks, SeaweedFS buckets/IAM, Authentik proxy applications, and
the two Terraform providers (`vault`, `kubernetes`).

## The "helm-linked terraform" concept

These modules don't take their own standalone configuration — they read the
same Helm chart `values.yaml` files (and per-cluster overrides) that
configure the rest of the cluster via ArgoCD, so a service's Vault secret,
SeaweedFS bucket, or Authentik proxy application is driven by the exact same
source of truth as its Kubernetes deployment.

Concretely:

- A flake input, `personalMonorepo`, is a non-flake GitHub checkout of this
  same repository, pinned to a branch (`project-rockhard/pki` as of writing —
  see `flake.nix`'s `inputs.personalMonorepo`).
- `lib/helm-value-loader.nix`'s `loadMergedValues "<chart>"` reads
  `kubernetes/helm-charts/k8s-resources/<chart>/values.yaml` from that input
  as the base values (converted from YAML to JSON via `yq`, evaluated with
  import-from-derivation), then, for every directory under
  `kubernetes/argocd/configuration-data/<env>/`, recursively merges that
  env's `master-stack.yaml` over the base values (the env's values win on
  conflict).
- The result is an attrset `{ <env1> = merged1; <env2> = merged2; ...;
  original = base; }` — one merged value set per configured environment, plus
  `original` (the unmodified base values, under the key every
  `configuration-data` directory would otherwise collide with).

Because `personalMonorepo` is a pinned GitHub ref and not this working tree,
changes to `values.yaml`/`master-stack.yaml` must be **pushed** before they
take effect here, and the pin bumped (see
[IMPLEMENTERS.md](IMPLEMENTERS.md) for details).

## How an environment is selected

Every resource these modules can create is gated with:

```nix
count = "\${var.<env> ? 1 : 0}";
```

and each generator that creates such a resource also declares a `bool`
Terraform variable named after that environment, defaulting to `false`. To
actually create resources for an environment, pass `-var <env>=true` (or
equivalently, set that Terraform input to `true`).

In practice you don't do this by hand: terragrunt sets
`basename(dirname(get_terragrunt_dir())) = true` as an input, so **the name
of the terragrunt cluster directory must exactly match the name of the
corresponding `kubernetes/argocd/configuration-data/<env>/` directory**
(e.g. a terragrunt directory named `qa-cluster/` enables the `qa-cluster`
environment).

## Modules

| Module | Purpose | Helm values consumed | Key variables | Provider notes |
| --- | --- | --- | --- | --- |
| `vault` | Creates the Vault Kubernetes auth backend + config, then one Vault KV-v2 mount/policy/auth-role/secret per enabled `vault-config` entry, per environment. | `vault-config` (every entry with `enabled: true`) | Per-entry `tfVar`s declared in `data.*` (e.g. `access_key`, `email`), plus `vault_url`, `vault_token`, `kubeconfig_*` (from the providers) | `standalone = true` — creates the `vault_auth_backend.kubernetes` resource itself. **Must be applied before every other module.** |
| `vault-pki` | Per environment, per non-template hostname in `istio-ingress-config`, creates a root CA, an intermediate CA, and a `cert-manager` Vault role/policy/Kubernetes auth role. | `istio-ingress-config` (`hostnames` list per env) | None beyond the environment bools | `standalone = false` — reads the Kubernetes auth backend via `data.vault_auth_backend.kubernetes`, so it needs `vault` applied first. |
| `authentik` | Per environment, per non-IP hostname, per `istio-ingress-config` entry with `auth.proxy.enabled: true`, creates an Authentik proxy provider, application, and outpost. | `istio-ingress-config` (every entry with `auth.proxy.enabled: true`) | `authentik_access_url`, `authentik_token`, `authentik_insecure`, `authentik_subdomain`, `secure` | `standalone = false`. Requires a running Authentik instance + API token. |
| `seaweedfs` | Per environment: an admin master secret (if `vault-config`'s `seaweedfs` entry is `enabled: true`), plus a bucket + IAM user + Vault secret for every `vault-config` entry with `seaweedfsSecret.enabled: true` (currently `rxresu`, `tandoor`). | `vault-config` (`seaweedfs` entry + any entry's `seaweedfsSecret.enabled`) | `access_key`, `secret_key` (admin creds), `seaweedfs_endpoint` (default `http://localhost:8333`), `kubeconfig_*` | `standalone = false`. Requires a running SeaweedFS instance reachable at `seaweedfs_endpoint`, with admin `access_key`/`secret_key` already provisioned. |

### Apply order

`vault` **must** be applied first — it creates the Kubernetes auth backend
(`vault_auth_backend.kubernetes`) that `vault-pki`, `authentik`, and
`seaweedfs` all read via `data.vault_auth_backend.kubernetes` (their
`standalone = false`). The other three modules are order-independent
relative to each other.

## Worked examples

### A `vault-config` entry (`kubernetes/helm-charts/k8s-resources/vault-config/values.yaml`)

```yaml
rxresu:
  enabled: false
  secretDestinationNamespace: misc
  postgresSecret: true
  seaweedfsSecret:
    enabled: true
  data:
    postgresUsername: rxresu
    postgresPassword:
      postgresPassword: true
    authSecret: {}
  namespace: misc
  mount: misc
```

- `enabled` gates whether the `vault` module creates this entry's secret at
  all for a given environment (`enabled` here is base-`false`; a cluster's
  `master-stack.yaml` flips it to `true` to opt that service in for that
  environment).
- `mount`/`namespace`/`serviceAccounts` (singular `namespace` in this file is
  informational only — the generator reads plural `namespaces`/
  `serviceAccounts`, falling back to `[mount or key]` / `[key]` if absent).
- `postgresSecret: true` additionally binds the Kubernetes auth role to the
  `postgres-cluster` service account in the `postgres` namespace.
- `seaweedfsSecret.enabled: true` is what makes the `seaweedfs` module create
  a bucket + IAM user + Vault secret for this entry (mount `seaweedfs`, path
  `rxresu-creds`).
- Each `data.*` value can be:
  - a literal string (`postgresUsername: rxresu`) — used as-is;
  - `{ value: ... }` — used as-is;
  - `{ tfVar: { name, type, description, default, sensitive } }` — resolved
    to `${var.<name>}`, and that variable is declared;
  - `{}` or omitted — a `random_password` is generated
    (`key_name` renames the generated resource; `postgresPassword: true`
    generates a special-character-free password, for safe use in
    Postgres/bash contexts).

### An `istio-ingress-config` entry (`kubernetes/helm-charts/k8s-resources/istio-ingress-config/values.yaml`)

```yaml
prowlarr:
  enabled: false
  prefixes:
    - /prowlarr
  destinationSvc: prowlarr.videos.svc.cluster.local
  auth:
    proxy:
      enabled: true
```

- `hostnames` (top-level, one per environment after merge) is what drives
  `vault-pki` — one root/intermediate CA pair per hostname.
- Per-entry `subdomain` + `destinationSvc` build the external/internal URLs
  an Authentik proxy provider forwards.
- `auth.proxy.enabled: true` is what makes the `authentik` module create a
  proxy provider/application/outpost for this entry.
- Entries whose hostname is a bare IP (e.g. the `external-user-1-cluster`
  example in `configuration-data/`) are skipped by `authentik`, since
  Authentik proxy auth needs a real hostname.

## Adding a seaweedfs-backed service

1. In the service's `vault-config` entry, add `seaweedfsSecret.enabled: true`
   (either directly in `values.yaml`, or via the relevant cluster's
   `master-stack.yaml`).
2. Make sure the `vault-config`'s own `seaweedfs` entry is `enabled: true`
   for that environment too (the `seaweedfs` module's admin master secret
   needs to exist for the provider to authenticate).
3. Push the change (helm-linked values are read from the pinned
   `personalMonorepo` input, not your working tree — see
   [IMPLEMENTERS.md](IMPLEMENTERS.md)) and update the flake input.

No module code changes are needed — the `seaweedfs` module derives its
service list entirely from `vault-config` at eval time.

## Adding a new module

1. Create `modules/<name>/infra.nix`. `flake.nix` auto-discovers any
   directory under `modules/` containing an `infra.nix` and turns it into a
   package — no registration needed.
2. Its function signature is `{ libFunctions, lib, inputs, pkgs, ... }:`.
   `libFunctions` is every function from every file under `lib/` merged
   together with `//` (see [IMPLEMENTERS.md](IMPLEMENTERS.md) for the
   caveats this implies).
3. Import the `vault`/`kubernetes` providers **by path**
   (`import ../../lib/vault-provider.nix { inherit lib; standalone = ...; }`),
   not via `libFunctions` — see [IMPLEMENTERS.md](IMPLEMENTERS.md).
4. Combine the provider(s) and your generated resources with `lib.mkMerge
   [ ... ]`.
5. Gate every resource you create with `count = "\${var.<env> ? 1 : 0}"` and
   declare that environment's `bool` variable (default `false`).
6. Build it with:

   ```sh
   nix build nix/terraform#packages.aarch64-linux.<name>
   ```

   `aarch64-linux` is only a build-system convention here — the output is
   plain Terraform JSON with no architecture dependency — but evaluation
   does need an `aarch64-linux` Nix builder, since loading Helm values goes
   through import-from-derivation.
7. For terragrunt to run it, the terragrunt directory name must equal the
   module name (`modules/<name>` ↔ `terragrunt/<cluster>/<name>/`).
