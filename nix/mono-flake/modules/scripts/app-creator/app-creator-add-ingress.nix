{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

app-creator-add-ingress = pkgs.writeShellScriptBin "app-creator-add-ingress" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}
'';
in

{
  environment.systemPackages = [
    app-creator-add-ingress
  ];
}