{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

$SCRIPT_NAME_BASE = pkgs.writeShellScriptBin "$SCRIPT_NAME_BASE" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}
'';
in

{
  environment.systemPackages = [
    $SCRIPT_NAME_BASE
  ];
}