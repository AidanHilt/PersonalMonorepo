# kubernetes/helm-charts — Implementers

Application and cluster-resource Helm charts, built on the bjw-s common
library chart.

See the [root IMPLEMENTERS.md](../../IMPLEMENTERS.md) for the repo-wide
convention and architecture overview.

## Overview

TODO

## Directory layout

- `applications/` — per-application charts (e.g. `audiobookshelf`,
  `paperless-ngx`), generally based on the bjw-s common library chart.
- `k8s-resources/` — cluster-resource charts, including `master-stack`
  (the chart ArgoCD uses to sync everything else — see
  [kubernetes/argocd](../argocd)).
- `lib/` — TODO: document shared chart library content.
- `templates/` — scaffolds for new charts.

## How it works

TODO

## Making changes

TODO

## Gotchas

TODO
