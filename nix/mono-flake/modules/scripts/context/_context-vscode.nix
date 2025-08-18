{ inputs, globals, pkgs, machine-config, lib, ...}:

let
context-vscode = pkgs.writeShellScriptBin "context-vscode" ''
#!/bin/bash

set -euo pipefail

if [[ ! -v ATILS_CURRENT_CONTEXT ]]; then
    echo "No context is currently activated. Please activate one using 'context-activate-context'"
    exit 1
fi

code $ATILS_CURRENT_CONTEXT_DIR
'';
in

{
  environment.systemPackages = [
    context-vscode
  ];
}