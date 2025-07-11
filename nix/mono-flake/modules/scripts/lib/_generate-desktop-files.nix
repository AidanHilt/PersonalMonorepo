{ inputs, globals, pkgs, machine-config, ...}:

let
generate-desktop-files = pkgs.writeShellScriptBin "generate-desktop-files" ''
#!/bin/bash

set -euo pipefail

root=$(mktemp -d)
mkdir -p "$root/etc/ssh"
ssh-keygen -t ed25519 -C "noname" -f "$root/etc/ssh/ssh_host_ed25519_key" -N "" > /dev/null 2>&1
echo $root | tr -d "\n"
'';
in

{
  environment.systemPackages = [
    generate-desktop-files
  ];
}