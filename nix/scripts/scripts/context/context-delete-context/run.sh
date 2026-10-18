#!/bin/bash

set -euo pipefail

# @lib: printing-and-output
# @lib: args-and-help

if [[ -z "${ATILS_CONTEXTS_DIRECTORY}" ]]; then
  echo "Error: ATILS_CONTEXTS_DIRECTORY environment variable is not set"
  echo "Please set it to your desired contexts directory path"
  exit 1
fi

CONTEXT_NAME=""

args_description "Delete a context directory."
args_example "$(basename "$0") -n my-context"
args_value "-n" "--name" CONTEXT_NAME "NAME" "Name of the context to delete"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

if [[ -z "$CONTEXT_NAME" ]]; then
  _context-context-selector
fi

# Check if context name is empty
if [[ -z "$CONTEXT_NAME" ]]; then
  echo "Error: Context name cannot be empty"
  exit 1
fi

# Create the full path
readonly CONTEXT_PATH="${ATILS_CONTEXTS_DIRECTORY}/${CONTEXT_NAME}"

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
read -rp "Are you sure you want to delete context '$CONTEXT_NAME'? (y/N) " response
case "$response" in
[yY] | [yY][eE][sS])
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
