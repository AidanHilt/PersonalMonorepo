{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

test = pkgs.writeShellScriptBin "test" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}
'';
in

{
  environment.systemPackages = [
    test
  ];
}