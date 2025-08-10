{ inputs, globals, pkgs, machine-config, lib, ...}:

let
context-list-contexts = pkgs.writeShellScriptBin "context-list-contexts" ''
#!/bin/bash

set -euo pipefail
if [[ -z "''${ATILS_CONTEXTS_DIRECTORY}" ]]; then
  echo "Error: ATILS_CONTEXTS_DIRECTORY environment variable is not set"
  echo "Please set it to your desired contexts directory path"
  exit 1
fi

echo "Available contexts:"
if [[ -d "$ATILS_CONTEXTS_DIRECTORY" ]]; then
  contexts=($(ls -1 "$ATILS_CONTEXTS_DIRECTORY" 2>/dev/null))
  if [[ ''${#contexts[@]} -eq 0 ]]; then
    echo "  (no contexts found)"
    return 1
  fi
  for context in "''${contexts[@]}"; do
    echo "  - $context"
  done
else
  echo "  (contexts directory does not exist)"
  return 1
fi
'';
in

{
  environment.systemPackages = [
    context-list-contexts
  ];
}