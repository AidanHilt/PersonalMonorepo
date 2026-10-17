# kubernetes

GitOps configuration for this repo's Kubernetes cluster(s): ArgoCD is
installed once per cluster, then reconciles everything else — including
itself — from this repository.

See [IMPLEMENTERS.md](IMPLEMENTERS.md) for architecture and how-it-works
detail; this README is about using and adapting the pattern.

## Layout

- `argocd/values.yaml` — Helm values for the ArgoCD installation itself
  (repository credentials, the `argocd-vault-plugin-helm` config
  management plugin used for secrets — see below).
- `argocd/configuration-data/<cluster>/` — per-cluster data:
  - `master-stack.yaml` — values for the `master-stack` chart (see
    below); this is the file that decides which apps are enabled on a
    given cluster and how.
  - `<app>.yaml` — per-app value overrides, consumed when that app opts
    into them (see "Enabling and configuring an app").
- `helm-charts/` — the Helm charts ArgoCD deploys. See
  [helm-charts/README.md](helm-charts/README.md).

## How apps get deployed: master-stack

`master-stack` (`helm-charts/k8s-resources/master-stack`) is itself an
ArgoCD `Application` whose chart renders one ArgoCD `Application` per
entry in its values. A cluster's `argocd/configuration-data/<cluster>/master-stack.yaml`
is layered on top of the chart's own `values.yaml` as the values source,
so each cluster can enable a different subset of apps.

Each top-level key in master-stack's values (other than a handful of
global keys — `env`, `hostnames`, `defaultGitRepo`, `gitRevision`,
`configuration`) is an app entry, and must set `enabled: true` to be
deployed. An entry is one of:

- **In-repo chart** — `gitPath: kubernetes/helm-charts/...` pointing at a
  chart in this repo.
- **Upstream chart** — `repo`, `chart`, and `version` pointing at an
  external Helm repo or OCI registry.

### Enabling and configuring an app

To enable an app on a cluster, add (or flip `enabled: true` on) its entry
in that cluster's `master-stack.yaml`. To give it cluster-specific
configuration, set `configuration.enabled: true` on the entry — this adds
`argocd/configuration-data/<cluster>/<app>.yaml` as an extra Helm values
file from a second `$values` source (see
`master-stack/templates/main.yaml`). That second source's branch is
`configuration.configurationRevision` if set (globally, in master-stack's
own values), otherwise it follows `gitRevision` — so configuration data
can be pinned independently of the app's own chart revision in unusual
cases, but normally moves with the rest of the repo.

Apps that use `secureValues` instead (see "Secrets" below) do **not** get
a `configuration.enabled` values file — all of their values must be
inline in `master-stack.yaml` under `secureValues`.

## Bootstrapping a cluster

Two supported paths to get ArgoCD and `master-stack` running on a new
cluster:

- **Manual / any cluster** — run
  [`argocd-install-argocd`](../nix/scripts/scripts/argocd-install-argocd)
  to `helm upgrade --install` ArgoCD using `argocd/values.yaml` (fetched
  from the `master` branch on GitHub; set `ARGOCD_TARGET_VERSION` to pin
  a chart version), then
  [`argocd-create-master-stack`](../nix/scripts/scripts/argocd-create-master-stack)
  to apply the `master-stack` `Application` itself (uses `CLUSTER_NAME`
  and the current/target branch). Afterwards,
  [`argocd-update-master-stack-revision`](../nix/scripts/scripts/argocd-update-master-stack-revision)
  can repoint a running `master-stack` `Application`'s sources at a
  different branch.
- **RKE2 node bootstrap** — on hosts provisioned with the `rke` server
  role, `_rke-bootstrap-resources.nix` drops an ArgoCD `HelmChart` CR and
  the `master-stack` `Application` straight into RKE2's manifest
  auto-deploy directory at startup, using the host's configured
  `k8s.clusterName`. This is the path used for machines managed via
  `nix/mono-flake`.

## Secrets

Two patterns are supported for getting secrets from Vault into the
cluster, depending on when the secret is needed.

**Preferred: Vault Secrets Operator (VSO).** The `vault-config` chart
(`helm-charts/k8s-resources/vault-config`) renders a `VaultAuth` and
`VaultStaticSecret` per app, syncing a Vault KV path into a native
Kubernetes `Secret` on a 30s refresh. The secret value never passes
through Git, ArgoCD, or Helm templating — the workload just mounts or
references the resulting `Secret` at runtime. Use this whenever a
long-running workload consumes the secret.

**Fallback: argocd-vault-plugin (AVP).** For apps where the secret is an
*input to Helm templating itself* — rendered into a larger generated
config document rather than mounted as its own `Secret` — `master-stack`
entries can set `secureValues` to a block of Helm values containing
`<path:argocd/data/...#key>` placeholders. ArgoCD then renders that app
through the `argocd-vault-plugin-helm` Config Management Plugin
(`argocd/values.yaml`) instead of its normal Helm path: the plugin runs
`helm template` and pipes it through `argocd-vault-plugin generate`,
substituting placeholders from Vault at sync time. AVP authenticates to
Vault via Kubernetes auth (no static token) using the
`argocd-repo-server` service account.

`video-stack-configuration` (`helm-charts/k8s-resources/video-stack-configuration`)
is the only app currently using AVP, and is a useful worked example: it
renders config files (e.g. `buildarr`-style configs for radarr, prowlarr,
jellyseerr) where each API key is interpolated into the larger rendered
document behind Helm conditionals, and the same secret (e.g.
`radarrApiKey`) is reused in several of those rendered files. There's also
no long-running workload of its own to attach a VSO-synced `Secret` to —
it's pure configuration. The rule of thumb: **VSO when a workload
consumes the secret at runtime, AVP when the secret must be baked into
rendered manifests at sync time.**

A couple of caveats if you use AVP: the substituted secret values end up
living in rendered manifests and ArgoCD's cache, not only in Vault; and
there's no 30s refresh — a Vault value change only takes effect on the
app's next sync.

## Helm charts

Application and cluster-resource charts live in `helm-charts/`; see
[helm-charts/README.md](helm-charts/README.md).
