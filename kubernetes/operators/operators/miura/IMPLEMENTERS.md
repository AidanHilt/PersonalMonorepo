# miura — Implementers

Miura is the Go operator that unfolds a `Function` (and, in future, a
`FunctionRepository`) into everything needed to run a Knative function
with Istio networking and JWT authentication. "miura" is the name of
this fold: spec in, generated cluster objects (build `Job`, Knative
`Service`, `VirtualService`, `RequestAuthentication` /
`AuthorizationPolicy`, `Trigger`, `PingSource`) out.

See [../../IMPLEMENTERS.md](../../IMPLEMENTERS.md) for how this operator
is built (Nix discovery, CRD/RBAC generation, chart assembly) — this
file covers miura's own API design and conventions, not the shared
build tooling.

## API

- Group: `miura.io` (placeholder — not yet registered/reserved
  anywhere outside this repo)
- Version: `v1alpha1`
- Scope: Namespaced
- Kinds: `Function` (`fn`), `FunctionRepository` (`funcrepo`)

Full field-level specs: [docs/function.md](docs/function.md) and
[docs/funcrepo.md](docs/funcrepo.md). **These spec sheets are
authoritative** — the Go types under `api/v1alpha1/` must be written to
match them, not the other way around.

## Cross-CRD conventions

- Spec and status field names use `camelCase`; enum values use
  `PascalCase`.
- `status.conditions` is `[]metav1.Condition`, following the standard
  Kubernetes condition shape (`type`, `status`, `reason`, `message`,
  `lastTransitionTime`, `observedGeneration`).
- `status.observedGeneration` is set on every reconcile to track
  whether status reflects the latest spec generation.
- Object reference fields follow an `xRef` naming pattern (e.g.
  `secretRef.name`, `gateway.name`), consistent with core Kubernetes API
  conventions.

## Decision log

**Authentik ownership.** Authentik (the IdP) configuration — OAuth2/OIDC
providers, clients, scope/group mappings — is owned by Terraform, not
miura. Miura only *enforces* JWT validation, via a generated
`RequestAuthentication` + `AuthorizationPolicy` scoped to the function's
gateway/host/path, validated against the operator-wide default issuer
(or a per-function override). Miura does not create or manage any
Authentik API object. The Authentik-side objects a function's
`triggers.http.auth.mode: Jwt` configuration requires are documented
from the user's perspective in [README.md](README.md), not implemented
here.

**JWT-only in v1alpha1.** `triggers.http.auth.mode` supports only `None`
and `Jwt`. A browser-based frontend that needs full authorization-code
flow can use PKCE directly against Authentik, or sit behind its own
backend-for-frontend (BFF) that holds the session and attaches a JWT to
calls into miura-fronted functions — so JWT-only is sufficient for
v1alpha1 without also implementing a `forwardAuth` mode. `forwardAuth`
(validating via a cookie/session through a mesh `ExtensionProvider`) is
deferred; see docs/function.md's open questions.

**Istio VirtualService over Gateway API.** Routing is expressed with
Istio's native `VirtualService` rather than the Kubernetes Gateway API,
matching how the rest of this environment's Istio installation is
configured elsewhere in the repo.

**`ko` as the builder.** Functions are built with `ko` rather than
buildpacks or a hand-rolled `go build` + image-assembly step: `ko` is
daemonless (no Docker-in-Docker needed in the build `Job`), requires no
Dockerfile, and is purpose-built for Go. This is also why miura's
function contract is Go-only for v1alpha1 — `ko` doesn't build other
languages.

**Function contract.** A function is a plain HTTP server (the standard
Knative contract: listen on `$PORT`). HTTP requests arrive as normal
HTTP; CloudEvents from `triggers.events`/`triggers.schedules` arrive as
HTTP POSTs, not through a separate event-handling SDK surface.

**Source polling.** Miura polls `git ls-remote` on `source.pollInterval`
to detect new commits on `source.ref` and trigger a rebuild, rather than
relying solely on webhooks (see docs/function.md's open questions for
webhook-based rebuild as a possible future addition).

**Operator-wide defaults.** The following are configured once at the
operator level, not per-`Function` (each is called out inline as "op
default" in docs/function.md): build registry (an external registry
reachable from the cluster — miura has no internal/in-chart registry and
assumes pushed images are public), default JWT issuer/JWKS URI, default
gateway, default domain (for `triggers.http.hostname`), default runtime
resources, default `source.pollInterval`, default `runtime.maxScale`,
and the build history length cap for `status.builds`.

## Reconciler implementation (`internal/controller/`)

The `FunctionReconciler` is split by concern, one file per stage of the
fold described at the top of this file:

- `function_controller.go` — top-level `Reconcile` orchestration (always
  patches `status` exactly once, via `client.MergeFrom`, regardless of
  which stage below returns early), RBAC markers, and `SetupWithManager`
  (owns `batch/v1` `Job`, plus the unstructured Knative `Service` and
  Istio `VirtualService` described below — `Owns()` accepts
  `unstructured.Unstructured` as long as its GVK is set before being
  passed in).
- `source.go` — resolves `spec.source.ref` using `go-git`'s `Remote.List`
  (an in-process, no-clone equivalent of `git ls-remote`) against an
  in-memory `storage/memory.Storage`; matches a branch first, then a
  tag. A 40-hex-character `ref` is treated as an already-resolved commit
  SHA with no remote lookup at all (there's no ref to list a bare SHA
  against). Requeues at `spec.source.pollInterval` (or the operator
  default) only for a resolved branch; tags/SHAs are never re-polled. A
  failed lookup is reported via the `SourceResolved` condition
  (`RefNotFound`, or `AuthFailed` for `transport.ErrAuthenticationRequired`/
  `ErrAuthorizationFailed`) rather than as a reconcile error, and is
  retried at the poll interval (or a 30s fallback when polling is
  disabled) so a since-fixed `ref` or transient network blip isn't stuck
  forever.
- `build.go` — the build `Job`. See "Build Job design" below.
- `serving.go` — the Knative `Service`. See "Why unstructured, not a
  typed client" below.
- `routing.go` — the Istio `VirtualService`. See "VirtualService routing
  choice" below.
- `status.go` — computes the `Ready` condition as the logical AND of
  whichever of `SourceResolved`/`Built`/`Routed` currently apply (see
  `presentConditionTypes`); deliberately excludes `AuthConfigured` since
  this round never sets it (see "Scope of this round" below) —
  including an condition type the reconciler never sets in that AND
  would wedge `Ready` at `False` forever.
- `unstructured.go` — one helper, `toJSONValue`, that round-trips a
  typed `corev1` value (e.g. `[]corev1.EnvVar`, `corev1.Probe`) through
  JSON into a plain `map[string]interface{}`/`[]interface{}` tree, for
  embedding into the unstructured Knative Service.

### Scope of this round

This implementation round targets `test/fixtures/valid/minimal.yaml`
(HTTP trigger, `auth.mode: None`) end-to-end. Deliberately **not**
implemented: JWT auth (`RequestAuthentication`/`AuthorizationPolicy`,
the `AuthConfigured` condition — `triggers.http.auth.mode: Jwt` is
accepted by the API but the reconciler does nothing extra for it yet),
`triggers.events`/`triggers.schedules` (`Trigger`/`PingSource`),
`source.secretRef` (private repository support — only public repos
resolve/clone), and `FunctionRepository`.

### Build Job design

One `batch/v1` `Job` per `(resolved commit, build-spec hash)` pair,
named deterministically `<function-name>-build-<hash10>` (`hash10` is
the first 10 hex characters of a SHA-256 over the commit plus every
`build.*`/`source.path` field that affects the built image — see
`buildSpecHash`). This is the whole rebuild-trigger mechanism: there is
no separate status field recording "last built spec"; the reconciler
just computes today's name and does a `Get` — `NotFound` means start a
new `Job`, found means read that `Job`'s current state. A commit or
build-spec change changes the hash, which changes the name, which is
indistinguishable from "no Job exists yet" and so always triggers a new
build, matching docs/function.md's "any change to source, ref, path, or
build.* triggers an immediate rebuild" rule without extra bookkeeping.

Each Job: owner-referenced to the `Function`, `ttlSecondsAfterFinished`
set (so finished Jobs clean themselves up — `status.builds[].jobName`
may reference a Job that no longer exists, as docs/function.md already
notes) and a small `backoffLimit`. Pod spec:

- An init container (image: `--git-image`, default `alpine/git`) runs
  `git clone <source.url> <checkout>; git checkout <commit>` into a
  shared `emptyDir` volume.
- The main container (image: `--ko-image`, default
  `ghcr.io/ko-build/ko`) has its `workingDir` set to
  `<checkout>/<source.path>` and runs `ko build --bare
  <build.mainPackage>`, with:
  - `KO_DOCKER_REPO=<registry>/<imageRepository>` (registry from
    `build.registry` or `--default-registry`; repository from
    `build.imageRepository` or `<namespace>/<name>`);
  - `KO_DEFAULTBASEIMAGE` from `build.baseImage` or
    `--default-base-image`;
  - every `build.env` entry passed through as a plain env var (sorted by
    key, for deterministic Job specs);
  - `DOCKER_CONFIG` pointing at a volume mounted from the push Secret
    (`build.pushSecretRef` or `--default-push-secret`), with only its
    `.dockerconfigjson` key projected to `config.json` — the shape
    `ko`'s underlying go-containerregistry keychain expects.
  - `terminationMessagePolicy: File` (the default, set explicitly for
    clarity): the container's script captures `ko build`'s stdout (the
    resulting `image@digest` on success) and writes it to
    `/dev/termination-log`.
- The reconciler reads that image back by listing the Job's Pods
  (`job-name=<job>` label, set automatically by the Job controller) and
  finding the `build` container's terminated status; a successfully
  terminated container with no termination message is treated as a
  failure (surfaced via the `Built` condition) rather than silently
  leaving `status.image` stale.
- A failed build (Job `Failed` condition true, i.e. `backoffLimit`
  exhausted) never touches `status.image` — the previous successful
  image keeps serving, per docs/function.md.

### Why unstructured, not a typed client

The Knative `Service` and Istio `VirtualService` are built and
reconciled as `unstructured.Unstructured` with their GVK set
explicitly, rather than importing `knative.dev/serving`/`istio.io/api`
client-go types. This keeps miura's own `go.mod` free of two more large
dependency trees (each with their own transitive version constraints to
reconcile against the pinned `k8s.io/*`/`sigs.k8s.io/controller-runtime`
versions) for what is, from miura's side, a small, mostly-static shape
of object. `controller-runtime`'s `client.Client` and `controllerutil`
(`CreateOrUpdate`, `SetControllerReference`) work against
`unstructured.Unstructured` exactly as they do against typed objects —
the only extra step is setting the GVK before `Get`/`Owns()`, since
there's no registration in `runtime.Scheme` to infer it from.

### VirtualService routing choice

The generated `VirtualService` does not address the Knative-generated
child `Service`/route directly. Instead, its `route[].destination.host`
is always the cluster-local `knative-local-gateway.istio-system.svc.
cluster.local` Service (the same internal gateway Knative's own
net-istio ingress controller routes through), with an HTTP header
operation (`headers.request.set`) rewriting `Host` to the Knative
Service's own cluster-local hostname,
`<name>.<namespace>.svc.cluster.local`. This is the documented pattern
for fronting a Knative Service with a hand-authored `VirtualService` on
a custom (non-Knative-owned) `Gateway`: Knative's internal routing is
entirely Host-header-based once traffic reaches the mesh, so forwarding
to the shared local gateway Service with the right `Host` header is
sufficient without needing to look up (or re-create logic for) whatever
Knative-managed child objects/routes exist for that revision. The
alternative — reading the Knative Service's own `status.address`/
generated child `Service`/`VirtualService` and pointing at those
directly — was not used, since it would require watching more
Knative-owned objects (racy against their own reconciliation) for no
benefit over the static gateway hostname.

### Operator-wide flags (`internal/config`)

`cmd/main.go` parses `internal/config.Config` from flags (each with an
`MIURA_*` environment-variable fallback, see `config.go`'s doc comment
for the full flag/env table) and passes it into `FunctionReconciler`.
The shared chart template
(`../../nix/templates/manager.yaml`) renders an optional
`manager.args`/`manager.env` list on the manager container, and
`operators/miura/chart/values.yaml` sets `manager.args` to one entry per
flag above with placeholder values — a real install is expected to
override at least `--default-registry` (and usually
`--default-push-secret`/`--default-domain`) via `--set-string`/`-f` at
install time, since there's no single correct default for those across
environments. `operators/miura/chart/templates/_helpers.tpl` is an
empty Helm partial (leading-underscore filename, never rendered as a
manifest) that exists purely so `chart/templates/` is a non-empty
directory git will actually track — see
[../../IMPLEMENTERS.md](../../IMPLEMENTERS.md) "Chart assembly": once
`chart/` exists at all (because of `chart/values.yaml`),
`mk-operator.nix` unconditionally copies `chart/templates/*`.

## Test fixtures

`test/` holds hand-authored material for exercising a running miura
installation against real `Function` objects — it is not Go unit tests
for the operator itself, and is out of scope for the Nix discovery in
[../../IMPLEMENTERS.md](../../IMPLEMENTERS.md) (its `go.mod` is a
separate, nested Go module; `operators/miura/`'s own module boundary
stops at `test/functions/go.mod`).

- `test/functions/` — a small, stdlib-only Go module with one `ko`-buildable
  `main` package per fixture function:
  - `cmd/hello` — plain HTTP server (the Knative Serving contract: listen
    on `$PORT`), used by the `minimal` and `http-jwt` fixtures below.
  - `cmd/event-sink` — logs every CloudEvent it receives; used by the
    `events` and `events-and-schedule` fixtures.
  - `cmd/cron-sink` — same behavior as `cmd/event-sink`, used by the
    `schedule` and `events-and-schedule` fixtures; both share their
    implementation via `internal/eventlog`.
  - Building these with `ko` (or any tool that clones `source.url` at
    `source.ref`) requires the branch under test to actually be pushed to
    the configured repo URL first — `ko` does not see local, uncommitted,
    or unpushed changes.
- `test/fixtures/valid/` — one `Function` per distinct spec shape the CRD
  supports, each pointing `source` at `test/functions/` above:
  - `minimal` — HTTP trigger, `auth.mode: None`.
  - `http-jwt` — HTTP trigger, `auth.mode: Jwt` with `audiences`,
    `requiredGroups`, and `requiredScopes` all set.
  - `events` — no HTTP trigger; a single `triggers.events[]` entry with a
    `filter`.
  - `schedule` — no HTTP trigger; a single `triggers.schedules[]` entry
    with `cron`, `data`, and `timezone` all set.
  - `events-and-schedule` — both `triggers.events[]` and
    `triggers.schedules[]` set on the same `Function`.
  - Every fixture's `spec.source.url`/`spec.source.ref` are the literal
    strings `${FIXTURE_REPO_URL}`/`${FIXTURE_REF}` — placeholders meant to
    be `envsubst`-rendered by `operator-test-reconcile`
    (`nix/scripts/scripts/operator-test-reconcile`), not applied as-is.
- `test/fixtures/invalid/` — one `Function` per CEL/validation rule in
  `api/v1alpha1/function_types.go`, each crafted to violate exactly that
  one rule so the API server must reject it: `name-too-long`,
  `minscale-gt-maxscale`, `no-triggers`, `jwt-mode-without-jwt`,
  `jwt-block-with-none-mode`, `issuer-without-jwksuri`, `bad-source-url`,
  `bad-source-path`, `pollinterval-too-short`. These also use the
  `${FIXTURE_REPO_URL}`/`${FIXTURE_REF}` placeholders wherever `source.url`
  itself isn't the thing under test.
- `FunctionRepository` has no fixtures — it isn't implemented yet (see
  [docs/funcrepo.md](docs/funcrepo.md)).

`operator-test-reconcile` is the generic (operator-agnostic) counterpart
to `operator-reconcile`: it reads only `operators/<name>/test/fixtures/
{valid,invalid}`, so it has no miura-specific knowledge beyond the
fixtures themselves.

## Gotchas

- `zz_generated.deepcopy.go` under `api/v1alpha1/` is not committed —
  it is generated at Nix build time (`controller-gen object` runs in a
  `preBuild` hook in `nix/mk-operator.nix`'s `binary` derivation) and is
  gitignored. A plain `go build`/`go vet` run outside that Nix build
  will fail to compile `api/v1alpha1` until you generate it yourself
  (`controller-gen object paths=./api/...`).
