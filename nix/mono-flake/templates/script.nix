{ inputs, globals, pkgs, machine-config, lib, ...}:

let
$SCRIPT_NAME_BASE = pkgs.writeShellScriptBin "$SCRIPT_NAME_BASE" ''
#!/bin/bash

set -euo pipefail
'';
in

{
  environment.systemPackages = [
    $SCRIPT_NAME_BASE
  ];
}