#!/bin/bash

set -euo pipefail

# @lib: printing-and-output
# @lib: args-and-help

# Check if ATILS_CONTEXTS_DIRECTORY is set
if [[ -z "${ATILS_CONTEXTS_DIRECTORY}" ]]; then
  echo "Error: ATILS_CONTEXTS_DIRECTORY environment variable is not set"
  echo "Please set it to your desired contexts directory path"
  exit 1
fi

# Function to validate context name
validate_context_name() {
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

args_description "Create a new context directory with an .env file and scripts subdirectory."
args_example "$(basename "$0") -n my-context"
args_value "-n" "--name" CONTEXT_NAME "NAME" "Name of the context to create"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

if [[ -z "$CONTEXT_NAME" ]]; then
  read -rp "Enter context name: " CONTEXT_NAME
fi

# Validate the context name
if ! validate_context_name "$CONTEXT_NAME"; then
  exit 1
fi

# Create the full path
CONTEXT_PATH="${ATILS_CONTEXTS_DIRECTORY}/${CONTEXT_NAME}"

# Check if directory already exists
if [[ -d "$CONTEXT_PATH" ]]; then
  echo "Context already exists, exiting"
  exit 1
fi

# Create the directory (including parent directories if needed)
echo "Creating context directory: $CONTEXT_PATH"
mkdir -p "$CONTEXT_PATH"

touch "$CONTEXT_PATH/.env"
mkdir "$CONTEXT_PATH/scripts"

# Verify creation
if [[ -d "$CONTEXT_PATH" ]]; then
  echo "✓ Successfully created context: $CONTEXT_NAME"
else
  echo "✗ Failed to create context"
  exit 1
fi
