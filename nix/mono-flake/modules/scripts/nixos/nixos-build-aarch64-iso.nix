{ inputs, globals, pkgs, machine-config, ...}:

let
nixos-build-aarch64-iso = pkgs.writeShellScriptBin "nixos-build-aarch64-iso" ''
#!/bin/bash

set -euo pipefail
nix build $PERSONAL_MONOREPO_LOCATION/nix/mono-flake#nixosConfigurations.iso-image-aarch64.config.system.build.isoImage
'';
in

{
  environment.systemPackages = [
    nixos-build-aarch64-iso
  ];
}