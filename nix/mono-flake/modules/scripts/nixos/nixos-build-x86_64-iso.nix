{ inputs, globals, pkgs, machine-config, lib, ...}:

let
nixos-build-x86_64-iso = pkgs.writeShellScriptBin "nixos-build-x86_64-iso" ''
#!/bin/bash

set -euo pipefail
nix build $PERSONAL_MONOREPO_LOCATION/nix/mono-flake#nixosConfigurations.iso-image-x86_64.config.system.build.isoImage
'';
in

{
  environment.systemPackages = [
    nixos-build-x86_64-iso
  ];
}