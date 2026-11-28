# nix/custom-images — Implementers

Nix-built container images (e.g. it-tools, transmission).

See the [root IMPLEMENTERS.md](../../IMPLEMENTERS.md) for the repo-wide
convention and architecture overview. Note: `custom-images/` at the repo
root is a separate, legacy Dockerfile-based project pending removal — see
the root IMPLEMENTERS.md's "Legacy" section.

## Overview

Nix-built container images, using
[nix2container](https://github.com/nlewo/nix2container) instead of
Dockerfiles. `flake.nix` discovers every directory under `images/` and
builds one package per directory for each supported system. There are
currently two images: `it-tools` and `transmission`, both
package-versioned (see below); there is no self-versioned example yet,
but both kinds are supported.

## Directory layout

- `images/` — per-image package definitions, tracked by `cog.toml` via
  `sync-cog-packages` (see `nix/scripts`).
- `flake.nix`, `flake.lock` — changes here trigger whole-fleet
  bump/release behavior in `.github/workflows/prepare-container-release.yml`
  and `.github/workflows/release-pkg-versioned-images.yml`.

## How it works

### Image discovery and the `images/<name>` contract

`flake.nix` reads every directory entry under `images/` and treats each
one as an image. Each image directory must contain:

- `values.nix` — a flat attrset setting exactly one of:
  - `tag = "<literal>";` — a **self-versioned** image. The version is
    this literal string, managed by cocogitto.
  - `versionPackage = "<nixpkgs attr path>";` — a **package-versioned**
    image. The version is read from `pkgs.<attr path>.version` at eval
    time.

  Setting both (or neither, once the image is no longer a work in
  progress) is an error — the flake `throw`s, and `sync-cog-packages`
  (see `nix/scripts/scripts/sync-cog-packages`) also rejects it when
  discovering packages, since both tools parse `values.nix` by matching
  the literal-string field with a regex rather than evaluating it, and
  require exactly one field to be unambiguous.
- `default.nix` — a function `{ pkgs, tag }:` returning the attrset
  nix2container's `buildImage` expects (`copyToRoot`, `config`, etc.),
  *without* a `name` or `tag` — the flake supplies those. See
  "Gotchas" below for why `default.nix` should not force its `tag`
  argument.

### Tag computation

For each image and system, the flake computes a base version (the
literal `tag`, or the resolved nixpkgs package's `.version` for
`versionPackage`), then appends the system to get the actual per-arch
image tag: `<version>-<system>` (e.g. `1.2.3-x86_64-linux`). The image
name is always `ghcr.io/aidanhilt/<name>` — this registry is hardcoded
intentionally; there is no per-image override. The built package also
exposes `imageName` and `imageTag` attributes (read by CI to construct
push/release refs) in addition to being a buildable nix2container
derivation.

### `all` and `default` outputs

The flake also exposes `all` (a `symlinkJoin` of every image package,
for building everything at once) and `default` (aliases `all`, falling
back to the first image if `all` is somehow absent).

### CI flow

Self-versioned and package-versioned images are released by different
workflows:

- **Self-versioned**: `.github/workflows/prepare-container-release.yml`
  runs `sync-cog-packages` to sync `cog.toml`, then `cog bump` (scoped
  to packages with qualifying commits, or force-bumping every
  self-versioned package when `flake.nix`/`flake.lock` changed) to
  produce `<name>-v<version>` tags. Those tags trigger
  `.github/workflows/release-internal-versioned-image.yml`, which
  builds and pushes a per-arch image for `x86_64-linux` and
  `aarch64-linux`, assembles a multi-arch index under the arch-less
  tag, tags it `latest`, and cuts a GitHub Release.
- **Package-versioned**: `.github/workflows/release-pkg-versioned-images.yml`
  runs on pushes touching `images/**` or the flake files, builds and
  pushes a per-arch image the same way, assembles the same kind of
  multi-arch index under the arch-less tag, but does **not** tag it
  `latest`. It then creates its own `<name>-v<version>` git tag and a
  GitHub Release, since there's no cocogitto tag to hang a release off.

Both workflows strip the known `-<system>` suffix off each per-arch
`imageTag` to derive the shared arch-less tag for the multi-arch index,
and refuse to publish if the `x86_64-linux` and `aarch64-linux` versions
disagree once that suffix is stripped.

## Checks

`flake.nix` exposes `checks.<system>` for every system it knows about, in
two tiers. That is what satisfies `agent-validate`'s flake contract: any
path at or below this flake's root is validated by building
`checks.<system>.agent-validate` instead of the legacy per-file lint/build
checks (`nixfmt` still runs in `agent-validate`'s `FORMAT` phase). Without
the attribute for the host's `builtins.currentSystem`, `agent-validate`
exits 24 before running anything — so a new system added to `linuxSystems`
or `darwinSystems` needs a `checks` entry in the same change.

Both tiers use the same naming convention: the aggregate is the
`agent-validate` **attribute**, pointing at the `aggregate-check`
**derivation**. The attribute name is fixed by the contract; the derivation
name is deliberately different (the same convention as `nix/mono-flake`,
`nix/scripts` and `nix/agentic-ai-stack`) so it is never confused with the
`agent-validate` script package from the scripts flake.

### Linux systems (`x86_64-linux`, `aarch64-linux`) — full checks

These are the systems images are actually built for (`linuxSystems`).
`aggregate-check` is an empty-marker `runCommand` whose `buildInputs` are
every image package plus the `statix` fixture, so
`nix build .#checks.<system>.agent-validate` performs a **real**
nix2container build of every image in `images/` and runs `statix` -- it is
not an evaluation-only check. That makes this aggregate considerably
heavier than a lint-only one; that is deliberate, since it is the only
automated proof that every image still builds. `all`/`default` are
`symlinkJoin`s of the same per-image packages and are excluded from
`buildInputs` on purpose.

This tier only builds on a Linux host. The repo's `linux-builder` is
provisioned (`/etc/nix/machines`) but not wired into `nix.conf` (there is no
`builders` line), so a macOS host cannot realise it — full Linux validation
has to run on a Linux machine.

### darwin systems (`x86_64-darwin`, `aarch64-darwin`) — statix only

There are no darwin images (see "Gotchas" for why the flake has no macOS
build path), so this tier is a runnable subset whose only job is to keep the
contract satisfiable on the macOS host: `checks.<system>.agent-validate`
points at an `aggregate-check` whose sole `buildInput` is that system's
`statix` fixture, built from `nixpkgs.legacyPackages.<system>`. It must
never reference an image package — those do not evaluate or build on
darwin, and the point of this tier is that it stays locally runnable.

### Fixtures

Each fixture is also exposed under its own attribute, so one can be
debugged directly with `nix build .#checks.<system>.<name>`:

- `statix` — `statix check` over the whole flake directory (`flake.nix`,
  `images/*/default.nix`, `images/*/values.nix`), not just the files a
  change happens to touch. Present in both tiers.
- `agent-validate` — the per-tier `aggregate-check` aggregate above.

## Making changes

### Adding or changing an image

Copy an existing directory under `images/` (`default.nix` + `values.nix`)
and adjust its contents. There is no manual registration step —
`sync-cog-packages` (run as a pre-commit hook and in CI) keeps
`cog.toml`'s generated section in sync with whatever self-versioned
images exist under `images/`. A matching Helm chart / ArgoCD app isn't
required to add an image, but is usually added alongside it for
deployment.

### Local testing

Build and load only for your native system:

```sh
nix run .#<name>.copyToDockerDaemon
```

There is no supported cross-build or macOS path; if you're on macOS,
build inside NixOS (e.g. a VM) instead.

### Fleet-wide effects of `flake.nix` / `flake.lock` changes

Editing `flake.nix` or `flake.lock` is treated as potentially affecting
every image, not just the one you're working on:

- `prepare-container-release.yml` force-bumps **every** self-versioned
  image (an unconditional patch bump, bypassing commit-log analysis).
- `release-pkg-versioned-images.yml` rebuilds and re-releases every
  package-versioned image.

Keep this in mind before touching the flake files for an unrelated
reason — it has repo-wide release consequences, not just for the image
you're editing.

## Gotchas

- `tag` and `versionPackage` must be bare, literal double-quoted
  strings in `values.nix` (no interpolation, no expressions) — both the
  flake and `sync-cog-packages` read them with simple text matching, not
  a Nix evaluator, by design. Setting both fields is a hard error in
  both tools; setting neither is silently treated as "not a package
  yet" (e.g. WIP scaffolding).
- The flake calls `import (imageDir + "/default.nix") { inherit pkgs; inherit (values) tag; }`
  unconditionally, even for package-versioned images whose `values.nix`
  has no `tag` attribute at all — `inherit (values) tag` would normally
  be an error in that case, but it only works because Nix attrset
  argument passing is lazy: the `tag` argument is never forced, because
  the flake immediately overrides the image's `tag` with its own
  computed value (`imageConfig // { tag = tag; ... }`) before building.
  `default.nix` implementations must not force their `tag` argument for
  anything (e.g. don't bake it into `config` yourself) — only the flake
  should ever read it.
- CI strips the trailing `-<system>` suffix off each per-arch `imageTag`
  to compute the shared, arch-less multi-arch tag, so the `x86_64-linux`
  and `aarch64-linux` builds of an image must resolve to the exact same
  base version — if they disagree, the release workflow errors out
  rather than publishing a mismatched index.
- There's no macOS support (dropped from `flake.nix`'s `systems` list);
  build NixOS instead if you need a local build on macOS.
- The legacy top-level `custom-images/` directory (Dockerfile-based) is
  an unrelated, separate project pending removal — see the root
  IMPLEMENTERS.md's "Legacy" section. Don't confuse the two.
