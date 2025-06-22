{ inputs, globals, pkgs, machine-config, ...}:

let
$SCRIPT_NAME = pkgs.writeShellScriptBin "$SCRIPT_NAME" ''
#!/bin/bash

set -euo pipefail
'';
in

{
  environment.systemPackages = [
    $SCRIPT_NAME
  ];
}