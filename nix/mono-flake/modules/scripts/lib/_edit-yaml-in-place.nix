{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

_edit-yaml-in-place = pkgs.writeShellScriptBin "_edit-yaml-in-place" ''
#!/bin/bash

set -euo pipefail

source ''${printing-and-output.printing-and-output}

FILENAME="$1"
YQ_STRING="$2"
TMP_FILE="/tmp/$(basename "''${FILENAME}")"

if [[ -z "''${FILENAME}" || -z "''${YQ_STRING}" ]]; then
  print_error "Both filename and yq string must be provided"
  exit 1
fi

print_status "Applying yq transformation to PRINT_DEBUGFILENAME}"

yq "''${YQ_STRING}" "''${FILENAME}" > "''${TMP_FILE}"
mv "''${TMP_FILE}" "''${FILENAME}"
'';
in

{
  environment.systemPackages = [
    _edit-yaml-in-place
  ];
}