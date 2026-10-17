# nix/custom-images — Implementers

Nix-built container images (e.g. it-tools, transmission).

See the [root IMPLEMENTERS.md](../../IMPLEMENTERS.md) for the repo-wide
convention and architecture overview. Note: `custom-images/` at the repo
root is a separate, legacy Dockerfile-based project pending removal — see
the root IMPLEMENTERS.md's "Legacy" section.

## Overview

TODO

## Directory layout

- `images/` — per-image package definitions, tracked by `cog.toml` via
  `sync-cog-packages` (see `nix/scripts`).
- `flake.nix`, `flake.lock` — changes here trigger whole-fleet
  bump/release behavior in `.github/workflows/prepare-container-release.yml`
  and `.github/workflows/release-pkg-versioned-images.yml`.

## How it works

TODO

## Making changes

TODO

## Gotchas

TODO
