# nix/mono-flake — Implementers

NixOS, nix-darwin and home-manager configuration for all hosts/machines in
this repository.

See the [root IMPLEMENTERS.md](../../IMPLEMENTERS.md) for the repo-wide
convention and architecture overview.

## Overview

TODO

## Directory layout

- `machines/` — per-host configuration.
- `modules/` — shared NixOS/nix-darwin modules.
- `home-manager/` — home-manager configuration.
- `lib-internal/` — internal Nix library code used by this flake.
- `templates/` — scaffolding templates (e.g. for new modules/machines).
- age-encrypted secrets (`*.age`) — TODO: document location and workflow.

## How it works

TODO

## Making changes

TODO

## Gotchas

TODO
