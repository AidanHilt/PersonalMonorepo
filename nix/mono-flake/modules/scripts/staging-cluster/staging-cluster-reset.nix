{ inputs, globals, pkgs, machine-config, lib, ...}:

let
staging-cluster-reset = pkgs.writeShellScriptBin "staging-cluster-reset" ''
#!/bin/bash

set -euo pipefail
'';
in

{
  environment.systemPackages = [
    staging-cluster-reset
  ];
}