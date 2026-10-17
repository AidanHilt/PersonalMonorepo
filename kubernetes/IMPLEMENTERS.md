# kubernetes — Implementers

ArgoCD root values, per-cluster configuration data, and the Helm charts
they deploy.

See the [root IMPLEMENTERS.md](../IMPLEMENTERS.md) for the repo-wide
convention and architecture overview.

## Overview

This directory covers `argocd/` (ArgoCD's own Helm values and per-cluster
values data) and, by reference, `helm-charts/` (the charts ArgoCD
deploys — see its own [IMPLEMENTERS.md](helm-charts/IMPLEMENTERS.md) for
chart-level detail, which is out of scope here).

## Directory layout

- `argocd/values.yaml` — root ArgoCD Helm values: repository credentials
  (including the `truecharts` OCI repo registration — see Gotchas), and
  the `argocd-vault-plugin-helm` Config Management Plugin (CMP)
  definition used for AVP-based secrets.
- `argocd/configuration-data/<cluster>/` — per-cluster values:
  - `master-stack.yaml` — values for
    `helm-charts/k8s-resources/master-stack`, which decides which apps
    are enabled for that cluster and how.
  - `<app>.yaml` — per-app value overrides, wired in via that app's
    `configuration.enabled: true` (see "How it works").

## How it works

`master-stack/templates/main.yaml` ranges over every key in its merged
values (chart `values.yaml` + the cluster's `master-stack.yaml`, minus
the global keys `env`, `hostnames`, `defaultGitRepo`, `gitRevision`,
`configuration`) and, for each `enabled: true` entry, renders an ArgoCD
`Application`:

- Source revision is `<entry>.version` if set, else the chart-level
  `gitRevision` (per-cluster, set in `master-stack.yaml`; this is
  distinct from `configuration.configurationRevision`, below).
- If the entry has no `secureValues`, it's templated as a normal Helm
  source. If `configuration.enabled` is also true, a second `$values`
  source is added pointing at
  `configuration.configurationRepo`/`configuration.configurationDirectory/<env>/<appName>.yaml`,
  at `configuration.configurationRevision` if set, else falling back to
  the same `gitRevision`.
- If the entry has `secureValues`, the `Application` source switches to
  `plugin: argocd-vault-plugin-helm` with the raw `secureValues` block
  passed as the `HELM_VALUES` env var — and `$isHelmChart` is false in
  this branch, so **no `configuration.enabled` value file is added, even
  if set**. All values for a `secureValues` app must be inline (in the
  chart's own `values.yaml` and/or the cluster's `master-stack.yaml`).
  `configuration-data/external-user-1-cluster/master-stack.yaml`'s
  `video-stack-configuration` entry is a worked example of the inline
  shape.
- `dependentApps` entries under an app follow the same two branches,
  rendered as their own `Application`.

### Secrets: AVP mechanics

The `argocd-vault-plugin-helm` CMP (defined once, in `argocd/values.yaml`,
and duplicated — see Gotchas — in the RKE2 bootstrap nix file) runs two
phases per sync of a `secureValues` app:

1. `init`: `helm dependency build` in the chart directory (resolves
   `Chart.lock`/subchart dependencies before templating; a no-op if the
   chart has none, as `video-stack-configuration` currently does).
2. `generate`: `helm template ... -f <(echo "$ARGOCD_ENV_HELM_VALUES")` —
   i.e. the `secureValues` block from `main.yaml` — piped into
   `argocd-vault-plugin generate -s argocd:argocd-vault-plugin-credentials`,
   which resolves the `<path:argocd/data/...#key>` placeholders against
   Vault and emits final manifests.

AVP authenticates to Vault via Kubernetes auth, not a static token: the
`argocd-vault-plugin-credentials` Secret (namespace `argocd`, created by
`helm-charts/k8s-resources/vault-config/templates/static.yaml`) sets
`AVP_AUTH_TYPE: k8s` and `AVP_K8S_ROLE: argocd`; the same template also
grants the `argocd-repo-server` ServiceAccount a `ClusterRoleBinding` to
`system:auth-delegator` so Vault's Kubernetes auth backend can perform
`TokenReview`s against it.

The plugin runs with `ARGOCD_EXEC_TIMEOUT: "600"` (seconds) and the
`avp-helm` sidecar container uses image `aidanhilt/atils-avp:latest` with
`imagePullPolicy: Always` (i.e. it always re-pulls on pod start, rather
than pinning a digest/tag).

## Making changes

- To change which apps run on a cluster, or their per-app config, edit
  the relevant `argocd/configuration-data/<cluster>/master-stack.yaml`
  and/or `<app>.yaml` — see the root README's
  ["Enabling and configuring an app"](README.md#enabling-and-configuring-an-app).
- To change ArgoCD's own install (repo credentials, the AVP CMP, repo
  server resources, etc.), edit `argocd/values.yaml` **and** the matching
  section of `_rke-bootstrap-resources.nix` (see Gotchas — these are
  not generated from a single source).
- After retargeting a running cluster's `master-stack` `Application` to a
  different branch (e.g. for testing a feature branch), use
  [`argocd-update-master-stack-revision`](../nix/scripts/scripts/argocd-update-master-stack-revision)
  rather than hand-patching — it walks every source on the `Application`
  and updates `targetRevision` in one pass.

## Gotchas

- **`secureValues` suppresses `configuration.enabled`.** `main.yaml` only
  adds the per-app values file when the Helm (non-plugin) branch is
  taken; an app with `secureValues` set ignores
  `configuration.enabled: true` entirely. Setting both is harmless but
  misleading — see the cleanup below.
- **AVP-rendered secrets persist outside Vault.** Once AVP substitutes a
  Vault value, it lives in the rendered manifest and ArgoCD's cache, not
  only in Vault, and only refreshes on the app's next sync (no 30s
  refresh like VSO).
- **ArgoCD config is duplicated.** `argocd/values.yaml` and the inline
  `HelmChart` `valuesContent` in `_rke-bootstrap-resources.nix` both
  define the full ArgoCD Helm values (repo credentials, AVP CMP, repo
  server env/containers) independently; a change to one must be mirrored
  in the other by hand.
- **TrueCharts OCI host mismatch.** Both `argocd/values.yaml` and
  `_rke-bootstrap-resources.nix` register `tccr.io/truecharts` as an
  ArgoCD OCI Helm repository credential, but the only consumer
  (`crafty-server` in `master-stack/values.yaml`) pulls from
  `oci://oci.trueforge.org/truecharts/crafty-4` — a different host. It's
  unclear from the source which host is intended; flagging rather than
  guessing.

## Areas for improvement

- **AVP vs. VSO `destination.transformation`.** AVP was chosen for
  `video-stack-configuration` because its secrets are inputs to Helm
  templating (interpolated into a larger generated config document,
  behind Helm conditionals that need the value at render time), which
  VSO's plain KV→Secret sync can't do. However, VSO's
  `destination.transformation` can template `Secret` contents, which may
  cover this case too — this wasn't factored into the original decision.
  Worth evaluating whether `video-stack-configuration` (and `secureValues`
  generally) could move to VSO, retiring the AVP CMP path.
- **Duplicated ArgoCD config** between `argocd/values.yaml` and
  `_rke-bootstrap-resources.nix` (see Gotchas) — a single source (e.g.
  having the nix bootstrap path fetch/render `values.yaml` instead of
  inlining a copy) would remove the keep-in-sync burden.
- **TrueCharts host mismatch** (see Gotchas) — the registered OCI repo
  credential (`tccr.io/truecharts`) and the host `crafty-server` actually
  pulls from (`oci.trueforge.org`) should likely agree; which one is
  correct isn't established here.
