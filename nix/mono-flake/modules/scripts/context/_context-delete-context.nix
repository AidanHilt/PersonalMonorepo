{ inputs, globals, pkgs, machine-config, lib, ...}:

let
context-delete-context = pkgs.writeShellScriptBin "context-delete-context" ''
#!/bin/bash

set -euo pipefail

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

list_contexts() {
  echo "Available contexts:"
  if [[ -d "$ATILS_CONTEXTS_DIRECTORY" ]]; then
    local contexts=($(ls -1 "$ATILS_CONTEXTS_DIRECTORY" 2>/dev/null))
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
  echo
  list_contexts
  echo
  read -p "Enter context name to delete:" CONTEXT_NAME
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
  list_contexts
  exit 1
fi

# Show what will be deleted
echo "Context to delete: $CONTEXT_NAME"
echo "Path: $CONTEXT_PATH"

# Show directory contents if not empty
if [[ -n "$(ls -A "$CONTEXT_PATH" 2>/dev/null)" ]]; then
  echo
  echo "Directory contents:"
  ls -la "$CONTEXT_PATH"
  echo
  echo "⚠️  WARNING: This directory is not empty!"
fi

# Confirmation prompt
echo
echo "Are you sure you want to delete this context? (y/N)"
read -r response
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

# Verify deletion
if [[ ! -d "$CONTEXT_PATH" ]]; then
  echo "✓ Context directory removed successfully"
else
  echo "✗ Context directory still exists"
  exit 1
fi
'';
in

{
  environment.systemPackages = [
  context-delete-context
  ];
}