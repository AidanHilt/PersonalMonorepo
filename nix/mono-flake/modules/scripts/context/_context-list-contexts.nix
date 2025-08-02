{ inputs, globals, pkgs, machine-config, lib, ...}:

let
context-list-contexts = pkgs.writeShellScriptBin "context-list-contexts" ''
#!/bin/bash

set -euo pipefail
'';
in

{
  environment.systemPackages = [
    context-list-contexts
  ];
}