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

Supported systems for the per-operator packages (`<name>-binary`,
`<name>-crds`, `<name>-rbac`, `<name>-image`, `<name>-chart`, `default`)
are `x86_64-linux` and `aarch64-linux` only, via
`flake-utils.lib.eachSystem`. Inputs: `nixpkgs` (`nixos-unstable`),
`flake-utils`, `nix2container` (`inputs.nixpkgs.follows = "nixpkgs"`).

`flake.nix` also exposes a `skopeo-nix2container` package — a
host-native build of nix2container's skopeo fork, which understands a
`nix:` transport that reads the image JSON an `n2c.buildImage` output
produces — for the wider system set `x86_64-linux`, `aarch64-linux`,
`x86_64-darwin`, `aarch64-darwin` (`nix2container.packages.${system}.skopeo-nix2container`,
merged into the Linux-only output set above via
`nixpkgs.lib.recursiveUpdate`). It exists so a non-Linux host (e.g. a
macOS dev machine) can copy a Linux-built operator image out of the Nix
store without executing any Linux-built binary itself; `operator-reconcile`
uses it to copy `nix:$IMAGE_PATH` to a `docker-archive:` tarball, which it
then feeds to `kind load image-archive`. Per-operator outputs themselves
remain Linux-only — `skopeo-nix2container` is the only cross-system
output this flake has.

`operators/miura/` is the one operator present today. Its Go module path
is `miura`, its CRD kind is `Function` (group `miura.io`, short name
`fn`), and its reconciler is `FunctionReconciler`. The `Function` fold is
implemented end-to-end for the minimal shape (HTTP trigger, `auth.mode:
None`) — source resolution, build `Job`, Knative `Service`, Istio
`VirtualService`. JWT auth, event/schedule triggers and
`FunctionRepository` are not reconciled yet; see
`operators/miura/IMPLEMENTERS.md` for the design, and its "Scope of this
round" for the exact boundary.

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

`buildGoModule` propagates this derivation's `preBuild` (and `env`) into
its internal `goModules` fixed-output derivation, which runs `go mod
vendor`. On current nixpkgs `env` carries `GOFLAGS=-mod=vendor`, so
without intervention `goModules` would run the `controller-gen object`
preBuild *before* `go mod vendor` has populated `vendor/`, failing with
"inconsistent vendoring". `binary` therefore sets `overrideModAttrs = _: {
preBuild = ""; }` to clear the preBuild just for `goModules`. This doesn't
change the vendored output or require a `vendorHash` bump — deepcopy
generation writes into the source tree, not `vendor/`.

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
  Nix-generated. See "Local dev loop" in [README.md](README.md) for how
  `operator-reconcile` overrides these for its own use.
- Optional `args`/`env` on the manager container, driven by
  `.Values.manager.args` (a plain string list, e.g.
  `["--foo=bar"]`) and `.Values.manager.env` (a list of
  `{name, value}`/`{name, valueFrom}` objects, the standard `corev1.EnvVar`
  shape) — each rendered with `{{- with ... }}`/`toYaml`/`nindent 12` only
  when the corresponding values key is set, so an operator that declares
  neither (every operator except `miura`, today) gets an unchanged
  `Deployment` with no `args`/`env` keys at all. This is the hook an
  operator uses to pass operator-wide flags/config into its manager
  binary without needing its own copy of the Deployment template — see
  `operators/miura/chart/values.yaml` for a real example (one `--flag=value`
  entry in `manager.args` per `internal/config` flag) and
  `operators/miura/IMPLEMENTERS.md` "Operator-wide flags" for the
  corresponding Go-side flag parsing.

- All names are static (not release-name-prefixed) — an accepted
  trade-off since each operator chart is expected to be installed once
  per cluster. Installing the same chart twice under different release
  names in one cluster will collide on these names.

## Checks

`flake.nix` exposes `checks.<system>`, split into two tiers.

**Linux (`x86_64-linux`, `aarch64-linux`) — the full tier.** `checks` is
`perOperatorChecks // { statix; agent-validate; }`:

- `<name>-vet` — one `go vet ./...` check per discovered operator
  (`operators.<name>.vet`, defined in `nix/mk-operator.nix` section
  "3b. go vet"). It is generated from the same operator list as the packages,
  so a new operator directory is vetted with no change to `flake.nix` or
  `nix/mk-operator.nix`. It follows the `crds`/`rbac` recipe exactly: a plain
  `stdenv.mkDerivation` that copies `binary.goModules` into `./vendor`, sets
  `GOFLAGS=-mod=vendor`, `GOPROXY=off`, and `HOME`/`GOCACHE` under `$TMPDIR`,
  runs `controller-gen object paths=./api/...` (required *first* — the api
  types only type-check once their generated `DeepCopyObject` methods exist,
  and vet loads the whole package graph), and then `go vet ./...`. Its `$out`
  is an empty marker directory: it exists only to fail when an operator does
  not vet cleanly.
- `statix` — `statix check .` over the whole flake source tree, not just the
  files a change touches. Every `.nix` file here is standalone and
  parseable (there are no `templates/`-style placeholders, unlike
  `nix/mono-flake`), so this fixture deliberately has no `--ignore`.
- `agent-validate` — the aggregate. An empty-output marker `runCommand`
  named `aggregate-check` whose `buildInputs` are every per-operator package
  (`binary`, `crds`, `rbac`, `image`, `chart`), every per-operator `<name>-vet`
  check, and the `statix` fixture — so `nix build
  .#checks.<system>.agent-validate` really builds the operators, not just
  evaluates them. `default` (the image+chart `linkFarm`) is deliberately not
  a build input: it only links outputs already covered.

The ATTRIBUTE name is fixed by `agent-validate`'s flake contract and must
stay `agent-validate`; the derivation it points at is deliberately named
`aggregate-check` so it is never confused with the `agent-validate` **script**
package from the `nix/scripts` flake (the same convention as
`nix/mono-flake`, `nix/scripts`, and `nix/agentic-ai-stack`). This aggregate
is what replaces the legacy per-file lint/build checks for any change at or
below this flake's root — `agent-validate` still runs its FORMAT phase
(nixfmt) over those files, but skips the per-file `LINT`/`BUILD_TEST` runs.

Because the aggregate really builds every operator package, it needs
`operators/<name>/go.sum` and `vendor-hash.nix` to be correct and in sync
(see "`vendor-hash.nix` handling" above) — a stale vendor hash fails the
whole check.

**darwin (`x86_64-darwin`, `aarch64-darwin`) — a runnable subset.** The
second `eachSystem` block (the one that also carries
`packages.skopeo-nix2container`) adds `checks.<system>` for the two darwin
systems only: the same `statix` fixture, built from that system's own `pkgs`,
plus an `agent-validate` attribute pointing at an `aggregate-check` whose
only build input is that fixture.

Three reasons for the split:

- Everything else in this flake is Linux-only (`binary`/`crds`/`rbac`/
  `image`/`chart` are built for `x86_64-linux`/`aarch64-linux`), so a darwin
  aggregate must not reference them — doing so would make the darwin
  `checks` unbuildable.
- `agent-validate` preflights `checks.$(nix eval --raw --impure --expr
  builtins.currentSystem).agent-validate` for every flake it touches and
  exits 24 when it is absent. The statix fixture is exactly enough to make
  that preflight satisfiable from a Mac, where the Linux tier cannot run.
- The gate matters: that `eachSystem` list also covers the two Linux
  systems, and `recursiveUpdate` gives the second argument precedence, so
  emitting the darwin tier unconditionally would silently replace the Linux
  `agent-validate` aggregate with the statix-only one.

Linux-side checks are therefore validated on a Linux host today. A
`linux-builder` is provisioned for this Mac in `/etc/nix/machines`, but it is
not wired up in `/etc/nix/nix.conf` (no `builders` line), so `nix build
.#checks.aarch64-linux.agent-validate` / the `-vet` checks cannot be realised
here yet. The darwin tier is a liveness check, not equivalent coverage.

## Making changes

- **Add an operator**: see "Adding a new operator" in
  [README.md](README.md) — no change to `flake.nix` or
  `nix/mk-operator.nix` is needed. The new operator is automatically covered
  by `checks.<system>.<name>-vet` and by the `agent-validate` aggregate (see
  "Checks" above).
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
- **`go.sum` + `vendor-hash.nix` together are what make a build
  hermetic.** Both are real for `operators/miura/` today (populated
  `go.sum`, an actual `sha256-...` in `vendor-hash.nix`), so
  `buildGoModule`'s `goModules` fixed-output derivation pins the whole
  dependency set and `binary`, `crds`, `rbac` and `<name>-vet` all build
  from that vendored tree with `GOPROXY=off` — the only step that can
  touch the network is `goModules` itself, and only on a cold
  store/cache. Bumping a dependency means refreshing `go.sum`
  (`go mod tidy` with network access) and re-pinning `vendorHash` (see
  "`vendor-hash.nix` handling" above); a wrong hash fails that FOD
  first, so `crds`/`rbac`/`<name>-vet` — and the `agent-validate`
  aggregate, see "Checks" above — never run at all.
- **Missing RBAC markers produce a silently incomplete role.** See "CRD
  + RBAC generation" above — there is no Nix-level check that every
  resource a reconciler touches has a corresponding
  `+kubebuilder:rbac` marker.
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
  integration.** The `checks.<system>` aggregate covers the Go side (operator
  package builds plus `go vet`) and statix, but nothing lints or templates
  the assembled charts; validating a chart still means building it and
  inspecting it by hand.
- **`imageTag`/`chartVersion` are an interim placeholder, not a real
  release scheme.** Every build's image and chart currently share one
  tag/version (`VERSION` file contents, or `shortRev`/`dirtyShortRev` for
  an uncommitted tree) — fine for local builds and the dev loop, but not
  a stable identity to publish against. An auto-incrementing semver
  scheme, plus actual image/chart publishing, is a separate, later piece
  of work; this flake does not push or publish anything today.
- **Much of the `Function` spec is accepted by the API but not
  reconciled.** Only the minimal shape is implemented (see "Overview"
  above): `triggers.http.auth.mode: Jwt` is validated but no
  `RequestAuthentication`/`AuthorizationPolicy` is generated,
  `triggers.events`/`triggers.schedules` generate no `Trigger`/
  `PingSource`, `source.secretRef` (private repos) is ignored, and the
  `FunctionRepository` kind exists only in `docs/funcrepo.md`. Worth
  knowing before relying on `miura` as a fully functioning operator — see
  `operators/miura/IMPLEMENTERS.md` "Scope of this round".
