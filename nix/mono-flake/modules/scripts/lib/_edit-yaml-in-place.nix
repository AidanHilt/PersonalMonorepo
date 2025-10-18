{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

_edit-yaml-in-place = pkgs.writeShellScriptBin "_edit-yaml-in-place" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}
'';
in

{
  environment.systemPackages = [
    _edit-yaml-in-place
  ];
}