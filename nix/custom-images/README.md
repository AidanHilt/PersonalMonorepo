# nix/custom-images

Nix-built container images, published to `ghcr.io/aidanhilt/<name>`. Each
image is a directory under `images/`, built with
[nix2container](https://github.com/nlewo/nix2container) rather than
Dockerfiles.

This project is self-contained and can be lifted out and adapted for your
own registry/images.

## Versioning

Every image is one of two kinds, set by its `values.nix`:

- **self-versioned** — `values.nix` has a `tag` field. The version is
  managed by cocogitto (conventional commits drive the bump).
- **package-versioned** — `values.nix` has a `versionPackage` field
  naming a nixpkgs attribute. The version tracks that nixpkgs package's
  version directly.

Supported systems are `x86_64-linux` and `aarch64-linux`.

## Building / loading an image locally

Build and load an image into your local Docker daemon for the system
you're running on:

```sh
nix run .#<name>.copyToDockerDaemon
```

for example:

```sh
nix run .#it-tools.copyToDockerDaemon
```

This only builds for your native system — cross-building isn't part of
the local workflow.

## Adding an image

Copy an existing directory under `images/` (needs a `default.nix` and a
`values.nix`), then adjust its contents. No manual registration step is
required: `cog.toml` is kept in sync automatically by a pre-commit hook
and CI (see
[nix/scripts/scripts/sync-cog-packages/README.md](../scripts/scripts/sync-cog-packages/README.md)).

## More

See [IMPLEMENTERS.md](IMPLEMENTERS.md) for how this project works
internally (flake layout, tag computation, CI flow) and what to watch out
for when changing it.
