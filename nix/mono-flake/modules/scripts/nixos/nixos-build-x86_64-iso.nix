{ inputs, globals, pkgs, machine-config, lib, ...}:

let
nixos-build-x86_64-iso = pkgs.writeShellScriptBin "nixos-build-x86_64-iso" ''
#!/bin/bash

set -euo pipefail
nix build $PERSONAL_MONOREPO_LOCATION/nix/mono-flake#nixosConfigurations.iso-image-x86_64.config.system.build.isoImage -o "$PERSONAL_MONOREPO_LOCATION/result/iso-image-x86_64"
find $PERSONAL_MONOREPO_LOCATION/result/iso-image-x86_64 -name "*.iso" -exec mv {} ./atils-nixos-x86_64.iso \;
'';
in

{
  environment.systemPackages = [
    nixos-build-x86_64-iso
  ];
}