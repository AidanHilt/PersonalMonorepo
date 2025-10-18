{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

helm-k8s-resource-new-stack = pkgs.writeShellScriptBin "helm-k8s-resource-new-stack" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}
'';
in

{
  environment.systemPackages = [
    helm-k8s-resource-new-stack
  ];
}