# kubernetes/argocd — Implementers

ArgoCD root values and per-cluster configuration data.

See the [root IMPLEMENTERS.md](../../IMPLEMENTERS.md) for the repo-wide
convention and architecture overview.

## Overview

TODO

## Directory layout

- `values.yaml` — root ArgoCD values (e.g. repository credentials, the
  `argocd-vault-plugin-helm` config management plugin).
- `configuration-data/<cluster>/` — per-cluster values, including each
  cluster's `master-stack.yaml` (values for
  `kubernetes/helm-charts/k8s-resources/master-stack`) and per-application
  value overrides.

## How it works

TODO

## Making changes

TODO

## Gotchas

TODO
