# kubernetes/operators — Implementers

A flake that discovers every operator under `operators/` and builds its
binary, CRDs, RBAC, container image and Helm chart — with zero
per-operator Nix code.

See the [root IMPLEMENTERS.md](../../IMPLEMENTERS.md) for the repo-wide
convention and architecture overview.

## Overview

Two files carry all the logic:

- `flake.nix` — the discovery layer. Finds every directory under
  `operators/` containing a `go.mod`, maps `nix/mk-operator.nix` over
  each, and exposes `<name>-binary`, `<name>-crds`, `<name>-rbac`,
  `<name>-image`, `<name>-chart` packages per operator plus a `default`
  `linkFarm` aggregate of every operator's image + chart.
- `nix/mk-operator.nix` — the shared builder invoked once per operator.
  Everything under `operators/` is data; adding an operator means adding
  a directory, not writing Nix.

Supported systems are `x86_64-linux` and `aarch64-linux`, via
`flake-utils.lib.eachSystem`. Inputs: `nixpkgs` (`nixos-unstable`),
`flake-utils`, `nix2container` (`inputs.nixpkgs.follows = "nixpkgs"`).

`operators/miura/` is the one operator present today. Its Go module path
is still `github.com/example/gitfunction-operator` and its CRD kind is
`GitFunction` (group `git.example.com`) — the directory was renamed to
`miura` but the Go module/CRD naming inside it was not. See "Gotchas".

## Directory layout

- `flake.nix` — operator discovery + package wiring (see above).
- `nix/mk-operator.nix` — the builder function, called once per
  discovered operator with `{ pkgs, lib, n2c, self, name, src }`.
- `nix/templates/manager.yaml` — the Helm template (ServiceAccount,
  ClusterRoleBinding, Deployment) shared by every operator's chart;
  copied verbatim into `templates/generated/manager.yaml` at build time
  and rendered by Helm, not by Nix.
- `operators/<name>/` — one directory per operator, each its own Go
  module. See the directory contract in [README.md](README.md).

## How it works

### Discovery

`go.mod` presence is the *only* signal `flake.nix` uses to mark a
directory under `operators/` as an operator — there is no separate
marker file that could drift out of sync with reality. The directory
name becomes the operator name used throughout (package attribute
prefixes, image name, chart name, `ClusterRole` name, etc.).

### `vendor-hash.nix` handling

Each operator is its own Go module, so one operator's dependency bump
never forces re-pinning every other operator's `vendorHash`.
`mk-operator.nix` reads `vendor-hash.nix` as plain Nix (`import`), which
must evaluate to a single string. A missing file throws an explicit
message (rather than a confusing failure inside `buildGoModule`)
instructing you to build once with a placeholder, read the hash Nix
reports, and paste it in as a bare string literal. A *wrong* hash gets
no special handling — Nix's normal fixed-output-derivation
hash-mismatch failure already reports the correct value.

### Binary

`buildGoModule { subPackages = [ "cmd" ]; version = "dev"; ... }` — the
binary is always `bin/cmd` inside the derivation regardless of operator
name, and `version` is hardcoded `"dev"` (distinct from the chart
version, which comes from `VERSION`/`shortRev`; see "Chart assembly").

### CRD + RBAC generation

Both run `controller-gen` over hardcoded paths:

- CRDs: `controller-gen crd paths=./api/... output:crd:dir=$out`.
- RBAC: `controller-gen rbac:roleName=<name> paths=./internal/controller/... output:rbac:dir=$out`,
  producing `role.yaml` with `ClusterRole` name `<name>`.

Both depend entirely on kubebuilder marker discipline in the Go source —
`+kubebuilder:object:root`/validation markers in `api/v1alpha1/*_types.go`
for CRDs, `+kubebuilder:rbac:groups=...,verbs=...` markers directly on
reconciler methods in `internal/controller/*_controller.go` for RBAC. If
a reconciler starts touching a new resource type without a corresponding
marker, the generated role is silently incomplete — this is the one
place generation depends on someone remembering to annotate, not
something Nix catches.

### Image

`n2c.buildImage { name = name; config.entrypoint = [ "${binary}/bin/cmd" ]; }`
— no other config (no labels, no user, no env). The chart's generated
values reference `image.imageDigest` from the built image; see
"Areas for improvement" for the unconfirmed-API caveat on that attribute
name.

### Chart assembly

`mk-operator.nix`'s `chart` derivation (no source archive — `unpackPhase
= "true"`, everything assembled from other derivations plus the
operator's own `chart/`):

- `crds/<file>.yaml` copied verbatim from the `<name>-crds` derivation.
  Helm never runs these through the template engine, and never touches
  them on `upgrade`/`uninstall`.
- `templates/generated/role.yaml` — copy of the generated RBAC role.
- `templates/generated/manager.yaml` — copy of
  `nix/templates/manager.yaml`.
- If `operators/<name>/chart/` exists, its `templates/*` are copied into
  the chart's top-level `templates/` (not `templates/generated/`) —
  kept visually separate so generated and hand-authored templates are
  never confused.
- `Chart.yaml` is always synthesized by `mk-operator.nix`, never read
  from `operators/<name>/chart/` — there is no per-operator `Chart.yaml`
  to maintain. `version` and `appVersion` are both set to: the contents
  of `operators/<name>/VERSION` if that file exists; else
  `self.shortRev`; else `self.dirtyShortRev` (uncommitted tree).
- `values.yaml` is a `yq eval-all` merge of two sources: the
  Nix-generated values (`{ image.digest, chart.version }`) and, if
  present, `operators/<name>/chart/values.yaml`. This is structured
  around key **ownership**, not merge precedence — `chart/values.yaml`
  is expected to simply never declare `image.digest` or `chart.version`
  in the first place, so correctness doesn't depend on which side of
  the `yq` expression wins.
- The assembled chart directory is also `helm package`d into
  `$out/packaged`.

### `manager.yaml`

Shared across every operator, templated by Helm at install time (not by
Nix at build time):

- `ServiceAccount` named `{{ .Chart.Name }}`.
- `ClusterRoleBinding` named `{{ .Chart.Name }}-manager-rolebinding`,
  bound to `ClusterRole` `{{ .Chart.Name }}` — must match the
  `roleName=<name>` passed to `controller-gen` in `mk-operator.nix`, even
  though the role manifest itself lives in a different generated file.
- `Deployment` named `{{ .Chart.Name }}-controller-manager`, `replicas:
  1`, container image
  `"{{ .Values.image.repository | default .Chart.Name }}@{{ .Values.image.digest }}"`,
  resources `requests: {cpu: 10m, memory: 64Mi}` /
  `limits: {memory: 256Mi}`.
- All names are static (not release-name-prefixed) — an accepted
  trade-off since each operator chart is expected to be installed once
  per cluster. Installing the same chart twice under different release
  names in one cluster will collide on these names.

## Making changes

- **Add an operator**: see "Adding a new operator" in
  [README.md](README.md) — no change to `flake.nix` or
  `nix/mk-operator.nix` is needed.
- **Change shared chart scaffolding** (ServiceAccount/RBAC
  binding/Deployment shape, resource requests, CRD/RBAC generation
  paths, `Chart.yaml` synthesis, the values merge rule): edit
  `nix/mk-operator.nix` and/or `nix/templates/manager.yaml` — these
  apply to every operator at once.
- **Change one operator's behavior**: edit inside
  `operators/<name>/` (Go source, `api/`/`internal/controller/`
  markers, optional `chart/`) — `flake.nix`/`mk-operator.nix` don't need
  to change.

## Gotchas

- **`miura` vs `gitfunction-operator` naming mismatch.** The operator
  directory is `operators/miura/`, but its Go module is still
  `github.com/example/gitfunction-operator`, its CRD kind is
  `GitFunction`, and its group is `git.example.com`. The directory
  (and therefore the Nix-level operator name, image name, chart name,
  `ClusterRole` name, etc.) was renamed to `miura` without renaming the
  Go module path or CRD naming inside it. Documented as-is, not fixed.
- **`operators/miura/` does not build without network access.** `go.sum`
  is empty and `vendor-hash.nix` holds a placeholder
  `sha256-AAAA...` string — see "Build readiness" in
  [README.md](README.md) for the exact fix steps.
- **Missing RBAC markers produce a silently incomplete role.** See "CRD
  + RBAC generation" above — there is no Nix-level check that every
  resource a reconciler touches has a corresponding
  `+kubebuilder:rbac` marker.
- **`reconcile-operator`'s `--set-string image.tag`/`image.pullPolicy`
  appear unused by the chart.** `manager.yaml`'s container image is
  `"{{ .Values.image.repository | default .Chart.Name }}@{{ .Values.image.digest }}"`
  — it references `image.repository` and `image.digest` only, with no
  `image.tag` or `image.pullPolicy` field anywhere in the template. But
  `nix/scripts/scripts/reconcile-operator/run.sh` installs with
  `--set-string image.tag="$DEV_TAG" --set-string image.pullPolicy=Never`
  after loading the image into `kind` under the `dev` tag. As written,
  those two `--set-string` values don't appear to be read by anything
  in this chart; the Deployment always pins by `image.digest`
  (unaffected by the dev tag/pull-policy override), and it's the
  `kind load docker-image` + `kubectl rollout restart` steps that
  actually get the freshly built image into the running pod. Flagging
  as observed from reading both files, not independently verified
  against a live cluster.
- **Static resource names mean one install per cluster.** See
  "`manager.yaml`" above — the chart was not designed for multiple
  concurrent releases of the same operator in one cluster.
- **No leader election, metrics, or health-check wiring.**
  `operators/miura/cmd/main.go`'s `ctrl.NewManager(...)` call passes only
  `Scheme`; no `LeaderElection`, `Metrics`, or `HealthProbeBindAddress`
  options are set, so none of controller-runtime's defaults for those
  are overridden or enabled beyond whatever controller-runtime does out
  of the box.

## Areas for improvement

- **`image.imageDigest` attribute name is unconfirmed** against the
  pinned `nix2container` version's actual API — `nix2container`'s
  digest-retrieval surface has changed across releases, so this should
  be checked against `nix2container.packages.<system>.nix2container`'s
  current return shape before relying on it in CI.
- **No `helm lint`/`helm template` flake `checks`, and no CI
  integration.** Both are absent entirely; validating a chart currently
  means building it and inspecting it by hand.
- **`miura`/`gitfunction-operator` naming mismatch** (see Gotchas) is
  unresolved — either the directory or the Go module/CRD naming could
  be brought in line with the other.
- **`reconcile-operator` vs. `manager.yaml` image reference interplay**
  (see Gotchas) — if the dev-loop flags are meant to have an effect, the
  chart would need an `image.tag`/`image.pullPolicy`-aware template
  path; if they're not meant to have one, the flags in
  `reconcile-operator` are dead weight.
- **Reconciler business logic is a stub.** `GitFunctionReconciler.Reconcile`
  in `operators/miura/internal/controller/gitfunction_controller.go`
  always returns `ctrl.Result{}, nil` — there is no actual
  reconciliation behavior yet, by design (out of scope for the
  build-tooling this scaffold exercises), but worth knowing before
  relying on `miura` as a functioning operator rather than a
  build-pipeline exercise.
