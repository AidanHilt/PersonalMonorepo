{ inputs, globals, pkgs, machine-config, lib, ...}:

let
staging-cluster-teardown = pkgs.writeShellScriptBin "staging-cluster-teardown" ''
#!/bin/bash

set -euo pipefail
'';
in

{
  environment.systemPackages = [
    staging-cluster-teardown
  ];
}