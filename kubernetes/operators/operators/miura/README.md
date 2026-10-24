# miura

> **Status:** this README describes miura's *target* API
> (`miura.io/v1alpha1`, `FunctionSpecification` / `FunctionRepository`).
> It is not all implemented yet — today the operator is a skeleton
> (kind `GitFunction`, group `git.example.com`, a stub reconciler). See
> [IMPLEMENTERS.md](IMPLEMENTERS.md) for the design and current status.

Miura turns a small spec into a running Knative function, fronted by
Istio with optional JWT authentication.

## Prerequisites

- Knative Serving
- Knative Eventing — only needed if a function uses `triggers.events` or
  `triggers.schedules`
- Istio, with a `Gateway` miura can route through
- Authentik as the identity provider (for `triggers.http.auth.mode: jwt`)
- A container registry — the bundled Zot chart works, or any other
  registry reachable from the cluster

## Function contract

A function is a Go `main` package in a git repository that runs a plain
HTTP server listening on the port given in the `PORT` environment
variable — the standard Knative Serving contract. Ordinary HTTP
requests arrive as normal HTTP requests. Events (`triggers.events`) and
schedules (`triggers.schedules`) also arrive as HTTP requests: specifically,
`POST` requests carrying a CloudEvent.

Functions are Go-only and are built with [`ko`](https://ko.build/) — no
Dockerfile is needed or used. The git repository's module root
corresponds to `source.path`, and the package to build corresponds to
`build.mainPackage` (relative to `source.path`).

A minimal function:

```go
package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "hello from miura")
	})
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	http.ListenAndServe(":"+port, nil)
}
```

## Example FunctionSpecification manifests

### Public HTTP function

```yaml
apiVersion: miura.io/v1alpha1
kind: FunctionSpecification
metadata:
  name: hello
spec:
  source:
    url: https://github.com/example/hello-fn
  build:
    mainPackage: ./cmd/hello
  triggers:
    http:
      auth:
        mode: none
```

### JWT-protected HTTP function

```yaml
apiVersion: miura.io/v1alpha1
kind: FunctionSpecification
metadata:
  name: billing-api
spec:
  source:
    url: https://github.com/example/billing-fn
  build:
    mainPackage: ./cmd/billing
  triggers:
    http:
      hostname: billing.example.internal
      auth:
        mode: jwt
        jwt:
          audiences:
            - billing-api
          requiredGroups:
            - billing-admins
```

### Event/schedule-only function (no HTTP)

```yaml
apiVersion: miura.io/v1alpha1
kind: FunctionSpecification
metadata:
  name: nightly-report
spec:
  source:
    url: https://github.com/example/report-fn
  build:
    mainPackage: ./cmd/report
  triggers:
    events:
      - broker: default
        filter:
          type: com.example.report.requested
    schedules:
      - cron: "0 2 * * *"
```

This function has no `triggers.http`, so its Knative Service is
cluster-local — it receives no ingress traffic and needs no JWT
configuration.

## Authentik objects required for JWT mode

Miura does not create or manage any object in Authentik. For a function
using `triggers.http.auth.mode: jwt`, Terraform must provision, ahead of
time:

- An OAuth2/OIDC provider in Authentik whose issuer matches either the
  operator-wide default issuer, or the function's
  `triggers.http.auth.jwt.issuer` override.
- Clients/scopes that issue the audience(s) listed in
  `triggers.http.auth.jwt.audiences`.
- Group and scope claims in the issued token matching any
  `requiredGroups` / `requiredScopes` the function specifies.

Miura only validates incoming JWTs against this configuration (via a
generated `RequestAuthentication` + `AuthorizationPolicy`); it has no
API integration with Authentik.

## Reading status

- `status.conditions` — check `Ready` for overall health; `SourceResolved`,
  `Built`, `Routed`, and `AuthConfigured` narrow down which stage is
  failing.
- `status.source.resolvedCommit` / `status.source.lastPolledTime` — what
  commit is currently built, and when it was last checked.
- `status.image` — the built image reference (with digest) currently
  deployed.
- `status.url` — the externally reachable URL, if `triggers.http` is set.
- `status.builds` — recent build history (commit, image, timing, result,
  backing `Job` name), capped to a small number of entries.

Status never echoes auth configuration (audiences, groups, scopes,
issuer, JWKS URI) — check the spec for that.

## FunctionRepository

`FunctionRepository` (generating `FunctionSpecification` objects from a
repo's directory layout) is planned but not yet available. See
[docs/funcrepo.md](docs/funcrepo.md).

## Further reading

- [docs/funcspec.md](docs/funcspec.md) — full `FunctionSpecification`
  field reference
- [docs/funcrepo.md](docs/funcrepo.md) — `FunctionRepository` basics
- [IMPLEMENTERS.md](IMPLEMENTERS.md) — design rationale and conventions
