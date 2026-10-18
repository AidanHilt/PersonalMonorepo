# kubernetes/helm-charts

The Helm charts ArgoCD deploys onto this repo's Kubernetes cluster(s). See
[IMPLEMENTERS.md](IMPLEMENTERS.md) for how the charts are built and how to
modify them; this README is about using and adding to them.

## Chart kinds

Every chart here is one of two kinds:

- **Application chart** (`applications/`) — deploys a service that affects
  or expands end-user functionality.
- **k8s-resources chart** (`k8s-resources/`) — creates resources that can
  support multiple apps, or use the configuration from an app.

## Layout

- `applications/` — per-application charts (22 currently), almost all
  built on the [bjw-s `common` library
  chart](https://bjw-s-labs.github.io/helm-charts/).
- `k8s-resources/` — cluster-resource charts, including `master-stack`
  (the chart ArgoCD uses to sync everything else — see
  [kubernetes/argocd](../argocd)).
- `lib/k8s-resources-common/` — a Helm library chart of functions shared
  between `k8s-resources` charts.
- `templates/` — scaffolds consumed by the chart-creation scripts below;
  not charts themselves.

## How charts are consumed

Charts are consumed only from this repo via `gitPath` entries in
`master-stack`'s values — they are not published to a Helm/OCI registry,
as there are no external users yet. See [kubernetes/README.md](../README.md)
for how `master-stack` wires an entry's `gitPath` into an ArgoCD
`Application`.

## Adding a new application

The recommended path is
[`app-creator-create-app`](../../nix/scripts/scripts/app-creator-create-app):
it interactively optionally scaffolds a new chart (via
`helm-new-application`, below), then adds the `master-stack` ArgoCD app
entry, ingress, homepage link, and any secrets/Postgres databases the app
needs.

To scaffold just the chart directly —
[`helm-new-application`](../../nix/scripts/scripts/helm-new-application)
`--chart-name <name>` copies `templates/application/` to
`applications/<name>/` and `envsubst`s the chart name into it. This is a
valid, supported way to work if you don't need the rest of
`app-creator-create-app`'s wiring.

The scaffold depends on the bjw-s `common` library chart; see
[IMPLEMENTERS.md](IMPLEMENTERS.md) for the expected `templates/common.yaml`
pattern.

## Adding a new k8s-resources chart

[`helm-new-k8s-resource`](../../nix/scripts/scripts/helm-new-k8s-resource)
`--chart-name <name> --resource-type <type>` copies
`templates/k8s-resources/` to `k8s-resources/<name>/` and `envsubst`s the
chart name and resource type into it. Using this directly (without going
through `app-creator-create-app`) is the normal way to add a
`k8s-resources` chart.

## Validation

`helm lint` is the only validation expected of a chart here.
