{ inputs, globals, pkgs, machine-config, lib, ...}:

let
contextSelector = import ./_context-context-selector.nix {inherit pkgs;};

context-delete-context = pkgs.writeShellScriptBin "context-delete-context" ''
#!/bin/bash

set -euo pipefail

source ${contextSelector.contextSelector}

if [[ -z "''${ATILS_CONTEXTS_DIRECTORY}" ]]; then
  echo "Error: ATILS_CONTEXTS_DIRECTORY environment variable is not set"
  echo "Please set it to your desired contexts directory path"
  exit 1
fi

show_usage() {
  echo "Usage: $0 --context <context_name>"
  echo "     $0 -c <context_name>"
  echo
  echo "Options:"
  echo "  --name, -n  Name of the context to delete"
  echo "  --help, -h     Show this help message"
  echo
}

CONTEXT_NAME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --name|-n)
      CONTEXT_NAME="$2"
      shift 2
      ;;
    --help|-h)
      show_usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option $1"
      show_usage
      exit 1
      ;;
  esac
done

if [[ -z "$CONTEXT_NAME" ]]; then
  _context-context-selector
fi

# Check if context name is empty
if [[ -z "$CONTEXT_NAME" ]]; then
  echo "Error: Context name cannot be empty"
  exit 1
fi

# Create the full path
readonly CONTEXT_PATH="''${ATILS_CONTEXTS_DIRECTORY}/''${CONTEXT_NAME}"

# Check if directory exists
if [[ ! -d "$CONTEXT_PATH" ]]; then
  echo "Error: Context '$CONTEXT_NAME' does not exist at:"
  echo "  $CONTEXT_PATH"
  echo
  context-list-contexts
  exit 1
fi

# Confirmation prompt
echo
read -p "Are you sure you want to delete this context? (y/N) " response
case "$response" in
  [yY]|[yY][eE][sS])
    echo "Deleting context..."
    ;;
  *)
    echo "Aborted."
    exit 0
    ;;
esac

# Delete the directory
if rm -rf "$CONTEXT_PATH"; then
  echo "✓ Successfully deleted context: $CONTEXT_NAME"
else
  echo "✗ Failed to delete context directory"
  exit 1
fi
'';
in

{
  environment.systemPackages = [
    context-delete-context
  ];
}