{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

$SCRIPT_NAME_BASE = pkgs.writeShellScriptBin "$SCRIPT_NAME_BASE" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

show_help () {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  # Description goes here
  echo ""
  echo ""
  echo "OPTIONS:"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --<>|-<>)

    shift 2
    ;;
    --help|-h)
    show_help
    exit 0
    ;;
    *)
    print_error "Unknown option: $1"
    exit 1
    ;;
  esac
done
'';
in

{
  environment.systemPackages = [
    $SCRIPT_NAME_BASE
  ];
}