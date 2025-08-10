{ inputs, globals, pkgs, machine-config, lib, ...}:

let
context-create-context = pkgs.writeShellScriptBin "context-create-context" ''
#!/bin/bash

set -euo pipefail

# Check if ATILS_CONTEXTS_DIRECTORY is set
if [[ -z "''${ATILS_CONTEXTS_DIRECTORY}" ]]; then
    echo "Error: ATILS_CONTEXTS_DIRECTORY environment variable is not set"
    echo "Please set it to your desired contexts directory path"
    exit 1
fi

# Function to validate context name
validate_CONTEXT_NAME() {
    local name="$1"

    # Check if name is empty
    if [[ -z "$name" ]]; then
        echo "Error: Context name cannot be empty"
        return 1
    fi

    # Check for invalid characters (allow letters, numbers, hyphens, underscores)
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Context name can only contain letters, numbers, hyphens, and underscores"
        return 1
    fi

    return 0
}

CONTEXT_NAME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--name)
      CONTEXT_NAME="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

if [[ -z "$CONTEXT_NAME" ]]; then
  read -p "Enter context name: " CONTEXT_NAME
fi

# Validate the context name
if ! validate_context_name "$CONTEXT_NAME"; then
  exit 1
fi

# Create the full path
context_path="''${ATILS_CONTEXTS_DIRECTORY}/''${CONTEXT_NAME}"

# Check if directory already exists
if [[ -d "$context_path" ]]; then
  echo "Context already exists, exiting"
  exit 1
fi

# Create the directory (including parent directories if needed)
echo "Creating context directory: $context_path"
mkdir -p "$context_path"

touch "$context_path/.env"

# Verify creation
if [[ -d "$context_path" ]]; then
    echo "✓ Successfully created context: $CONTEXT_NAME"
else
    echo "✗ Failed to create context"
    exit 1
fi
'';
in

{
  environment.systemPackages = [
    context-create-context
  ];
}