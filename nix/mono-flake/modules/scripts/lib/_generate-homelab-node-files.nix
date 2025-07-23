{ inputs, globals, pkgs, machine-config, lib, ...}:

let
generate-homelab-node-files = pkgs.writeShellScriptBin "generate-homelab-node-files" ''
#!/bin/bash

set -euo pipefail

root=$(mktemp -d)
mkdir -p "$root/etc/ssh"
ssh-keygen -t ed25519 -C "noname" -f "$root/etc/ssh/ssh_host_ed25519_key" -N "" > /dev/null 2>&1
mkdir -p "$root/etc/rancher/rke2"
age -i ~/.ssh/id_ed25519 -d "$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/secrets/rke-config-$1.age" > "$root/etc/rancher/rke2/config.yaml"
echo $root | tr -d "\n"
'';
in

{
  environment.systemPackages = [
    generate-homelab-node-files
  ];
}