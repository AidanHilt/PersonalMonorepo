{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

vault-provision = pkgs.writeShellScriptBin "vault-provision" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

valid_run="false"

if [[ -v TG_WORKING_DIR ]]; then
  valid_run="true"
  echo "After first if: $valid_run"
fi

if [[ -f vault/terragrunt.hcl ]] || [[ -f terragrunt.hcl ]]; then
  valid_run="true"
  echo "After second if: $valid_run"
fi

if valid_run="false"; then
  print_error 'Please set TG_WORKING_DIR, or navigate to $TG_WORKING_DIR or $TG_WORKING_DIR/vault'
fi
'';
in

{
  environment.systemPackages = [
    vault-provision
  ];
}