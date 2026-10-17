# nix/terraform — Implementers

Nix modules that generate Terraform (via terranix) for Authentik,
SeaweedFS, Vault, and Vault PKI. The generated modules are run by
[terragrunt/](../../terragrunt).

See the [root IMPLEMENTERS.md](../../IMPLEMENTERS.md) for the repo-wide
convention and architecture overview.

## Overview

TODO

## Directory layout

- `flake.nix` — discovers and builds one Terraform package per directory
  under `modules/` that has an `infra.nix`.
- `modules/<name>/infra.nix` — per-module Terraform generation (observed:
  `authentik`, `vault`, `vault-pki`; TODO: confirm the full/current set,
  including SeaweedFS).
- `lib/` — shared helper code (e.g. `kubernetes-provider.nix`,
  `vault-provider.nix`, `helm-value-loader.nix`,
  `authentik-resource-generator.nix`).

## How it works

TODO

## Making changes

TODO

## Gotchas

TODO
