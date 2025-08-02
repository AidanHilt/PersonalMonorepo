{ inputs, globals, pkgs, machine-config, lib, ...}:

let
context-create-context = pkgs.writeShellScriptBin "context-create-context" ''
#!/bin/bash

set -euo pipefail
'';
in

{
  environment.systemPackages = [
    context-create-context
  ];
}