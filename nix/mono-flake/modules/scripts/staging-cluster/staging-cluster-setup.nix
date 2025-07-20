{ inputs, globals, pkgs, machine-config, lib, ...}:

let
staging-cluster-setup = pkgs.writeShellScriptBin "staging-cluster-setup" ''
#!/bin/bash

set -euo pipefail
'';
in

{
  environment.systemPackages = [
    staging-cluster-setup
  ];
}