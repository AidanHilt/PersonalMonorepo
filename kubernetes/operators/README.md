# Operator Building Flake

Implementation of the design spec: one flake, `operators/` discovery, zero
per-operator Nix code. See `flake.nix` and `nix/mk-operator.nix` for the
two files that carry all the logic; everything under `operators/` is data.

## What's here

- `flake.nix` — discovery layer. Finds every directory under `operators/`
  containing a `go.mod`, maps `nix/mk-operator.nix` over each, exposes
  `<name>-binary`, `<name>-crds`, `<name>-rbac`, `<name>-image`,
  `<name>-chart` packages per operator, plus a `default` aggregate.
- `nix/mk-operator.nix` — the shared builder. Every convention from the spec
  (vendor-hash handling, CRD/RBAC generation paths, chart assembly,
  key-ownership merge rule) lives here, commented at the point it's encoded.
- `nix/templates/manager.yaml` — the shared manager Deployment /
  ServiceAccount / ClusterRoleBinding template, copied into every chart's
  `templates/generated/`.
- `operators/gitfunction-operator/` — a worked example exercising the full
  directory contract, including the *optional* `chart/` override (zot
  registry Deployment/Service/PVC) to demonstrate the merge-by-ownership
  path and the "chart is still valid with zero override dir" path.

## Deviations / things called out explicitly in the spec

- **Multi-arch.** The spec's own `flake.nix` sketch referenced an undefined
  `system` and flagged multi-arch as "not decided yet" as a design matter,
  but also carried an explicit inline note asking for x86_64-linux and
  aarch64-linux support. I took that note as a live requirement and wired
  up `flake-utils.lib.eachSystem` for both, rather than leaving `system`
  undefined.
- **`image.imageDigest`.** The spec flagged this attribute name as
  unconfirmed against nix2container's actual API. Left as-is with the same
  caveat inline — nix2container's digest-retrieval surface has changed
  across releases, so pin the input and check `nix2container.packages.<system>.nix2container.buildImage`'s
  current return shape before relying on this in CI.
- **`helm lint` / `helm template` as a Nix `checks` output** and **CI
  integration** — both explicitly listed in the spec as deferred/out of
  scope, so neither is implemented here.

## What won't build out of the box

This container has no network access to the Go module proxy, so two things
in `operators/gitfunction-operator/` are placeholders you'll need to fill
in against a real network before `nix build` succeeds:

1. **`go.sum`** is empty. Run `go mod tidy` inside
   `operators/gitfunction-operator/` with network access to populate it.
2. **`vendor-hash.nix`** contains a dummy `sha256-AAAA...` string. Run

   ```
   nix build .#gitfunction-operator-image
   ```

   once — this is exactly the flow the `throw` message in
   `mk-operator.nix` describes — and paste the hash Nix reports back
   into `vendor-hash.nix`.

Everything else (the discovery logic, the CRD/RBAC generation wiring, the
chart assembly and merge rules, the `Chart.yaml` synthesis) has no external
dependency beyond `nixpkgs` and `nix2container` and should work as soon as
those two placeholders are real.

## Adding a new operator

Per the contract: add a directory under `operators/` with `go.mod`,
`go.sum`, `vendor-hash.nix`, `cmd/main.go`, `api/v1alpha1/*_types.go` and
`internal/controller/*_controller.go` following kubebuilder marker
conventions. Optionally add `VERSION` and/or `chart/values.yaml` +
`chart/templates/*`. Nothing in `flake.nix` or `nix/mk-operator.nix`
changes.
