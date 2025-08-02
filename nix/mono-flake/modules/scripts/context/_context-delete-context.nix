{ inputs, globals, pkgs, machine-config, lib, ...}:

let
context-delete-context = pkgs.writeShellScriptBin "context-delete-context" ''
#!/bin/bash

set -euo pipefail
'';
in

{
  environment.systemPackages = [
    context-delete-context
  ];
}