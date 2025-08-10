{ inputs, globals, pkgs, machine-config, lib, ...}:

let
_context-activate-context = pkgs.writeShellScriptBin "_context-activate-context" ''
#!/bin/bash

set -euo pipefail
'';
in

{
  environment.systemPackages = [
    _context-activate-context
  ];
}