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

## Gotchas

- `zz_generated.deepcopy.go` under `api/v1alpha1/` is not committed —
  it is generated at Nix build time (`controller-gen object` runs in a
  `preBuild` hook in `nix/mk-operator.nix`'s `binary` derivation) and is
  gitignored. A plain `go build`/`go vet` run outside that Nix build
  will fail to compile `api/v1alpha1` until you generate it yourself
  (`controller-gen object paths=./api/...`).
