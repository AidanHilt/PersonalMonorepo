{ inputs, globals, pkgs, machine-config, lib, ...}:

let
vault-retrieve-token = pkgs.writeShellScriptBin "vault-retrieve-token" ''
#!/bin/bash

set -euo pipefail

if [[ -v VAULT_TOKEN ]]; then
  echo "VAULT_TOKEN not set, aborting"
  exit 1
fi

_copy-text-to-clipboard "$VAULT_TOKEN"
'';
in

{
  imports = [
    ../lib/_copy-text-to-clipboard.nix
  ];

  environment.systemPackages = [
    vault-retrieve-token
  ];
}