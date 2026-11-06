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
is `miura`, its CRD kind is `Function` (group `miura.io`, short name
`fn`), and its reconciler is `FunctionReconciler`. The API types are
implemented; the reconciler is still a stub. See "Gotchas".

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

The `binary` derivation also carries `nativeBuildInputs = [
pkgs.kubernetes-controller-tools ]` and a `preBuild` hook that runs `controller-gen
object paths=./api/...` before `buildGoModule` compiles the module. This
generates each operator's `zz_generated.deepcopy.go` (the
`DeepCopyObject` methods required by `runtime.Object`) at build time
rather than it being committed to the source tree — so there is no
generated deepcopy file to keep in sync by hand, but it also means a
plain `go build`/`go vet` run outside this Nix build will fail to
compile `api/v1alpha1` until you run `controller-gen object` yourself.
Operators are expected to `.gitignore` their own
`zz_generated.*.go` files (see `operators/miura/.gitignore`).

### CRD + RBAC generation

Both run `controller-gen` over hardcoded paths:

- CRDs: `controller-gen object paths=./api/...` (deepcopy, see below) then
  `controller-gen crd paths=./api/... output:crd:dir=$out`.
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

Unlike the `binary` derivation, `crds` and `rbac` are plain
`stdenv.mkDerivation`s, not `buildGoModule` — but controller-gen still
needs to load (`go list`) the operator's packages to inspect types, which
requires a `go` binary *and* resolvable module dependencies, not just the
controller-gen binary itself. So both derivations carry `pkgs.go` in
`nativeBuildInputs` alongside `pkgs.kubernetes-controller-tools`, and their
`buildPhase` copies `binary.goModules` (the vendor directory `buildGoModule`
produces for the `binary` derivation, built from the same `go.sum`/
`vendor-hash.nix`) into `./vendor`, makes it writable (`chmod -R u+w`), and
sets `GOFLAGS=-mod=vendor`, `GOPROXY=off`, and `HOME`/`GOCACHE` under
`$TMPDIR` so `go` resolves dependencies from that vendor copy instead of
trying — and failing, sandboxed — to reach the network or write outside the
build sandbox. This means `crds`/`rbac` depend on `binary` evaluating
successfully (same `go.sum`/`vendor-hash.nix` correctness requirement as
the `binary` derivation itself — see "`vendor-hash.nix` handling" above);
if those are stale or placeholders, `binary.goModules` fails before
`crds`/`rbac` ever reach controller-gen.

The `crds` derivation additionally runs `controller-gen object` (the same
deepcopy generation the `binary` derivation's `preBuild` performs) *before*
`controller-gen crd`: controller-gen loads the full package graph to
resolve CRD schemas, and API types like `Function` only satisfy
`runtime.Object` (and so type-check during package loading) once their
generated `DeepCopyObject` method exists. Without generating that first,
package loading fails before CRD generation gets a chance to run. `rbac`
doesn't need this, since RBAC generation only reads marker comments on
reconciler methods, not the API types' method sets.

### Image

`n2c.buildImage { name = name; tag = imageTag; config.entrypoint = [ "${binary}/bin/cmd" ]; }`
— no other config (no labels, no user, no env). `imageTag` is an interim
placeholder equal to `chartVersion` (see "Chart assembly" below) — every
build's image gets a tag equal to its own chart version for now. This is
meant to be replaced by an auto-incrementing semver scheme once charts are
actually published; it is not meant to be relied on as a stable identity
beyond that.

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
  Nix-generated values (`{ image.tag, chart.version }`) and, if
  present, `operators/<name>/chart/values.yaml`. This is structured
  around key **ownership**, not merge precedence. `chart.version` is
  always Nix-owned; `image.tag` is only a Nix-*supplied default* (so the
  chart is installable out of the box) that `--set`/`--set-string` or an
  operator's own `chart/values.yaml` is free to override. Either way,
  `chart/values.yaml` is expected to simply never declare `image.tag` or
  `chart.version` itself, so correctness doesn't depend on which side of
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
  `"{{ .Values.image.repository | default .Chart.Name }}:{{ .Values.image.tag }}"`,
  `imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}`,
  resources `requests: {cpu: 10m, memory: 64Mi}` /
  `limits: {memory: 256Mi}`. `image.repository` is optional and defaults
  to the chart name; `image.tag` is the Nix-generated default described
  above (overridable); `chart.version` (used in `Chart.yaml`) is always
  Nix-generated. See "Local dev loop" for how `reconcile-operator`
  overrides these for its own use.
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

- **`zz_generated.deepcopy.go` is generated at build time, not
  committed.** `nix/mk-operator.nix`'s `binary` derivation runs
  `controller-gen object paths=./api/...` in a `preBuild` hook before
  `buildGoModule` compiles the module, and `operators/miura/.gitignore`
  excludes the generated file from the source tree. A plain `go
  build`/`go vet` run outside that Nix build will fail to compile
  `api/v1alpha1` until you generate it yourself.
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

- **No `helm lint`/`helm template` flake `checks`, and no CI
  integration.** Both are absent entirely; validating a chart currently
  means building it and inspecting it by hand.
- **`imageTag`/`chartVersion` are an interim placeholder, not a real
  release scheme.** Every build's image and chart currently share one
  tag/version (`VERSION` file contents, or `shortRev`/`dirtyShortRev` for
  an uncommitted tree) — fine for local builds and the dev loop, but not
  a stable identity to publish against. An auto-incrementing semver
  scheme, plus actual image/chart publishing, is a separate, later piece
  of work; this flake does not push or publish anything today.
- **Reconciler business logic is a stub.** `FunctionReconciler.Reconcile`
  in `operators/miura/internal/controller/function_controller.go`
  always returns `ctrl.Result{}, nil` — the `Function` API types are
  implemented, but there is no actual reconciliation behavior yet; that
  is a separate, later change. Worth knowing before relying on `miura`
  as a functioning operator rather than an API-schema/build-pipeline
  exercise.
