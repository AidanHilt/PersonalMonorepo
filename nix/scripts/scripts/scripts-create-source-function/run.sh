#!/bin/bash

# @lib: printing-and-output
# @lib: args-and-help
# @lib: env-checks

set -euo pipefail

SOURCE_FUNCTION_NAME_ARG=""

args_description "Create a new source function directory with a blank source.sh file"
args_example "$(basename "$0") --source-function-name my-function"
args_value "" "--source-function-name" SOURCE_FUNCTION_NAME_ARG "NAME" "Name of the source function to create (prompted if omitted)"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

require_monorepo

if [[ -z "$SOURCE_FUNCTION_NAME_ARG" ]]; then
  print_debug "No source function name provided, prompting user"
  read -r -p "Enter source function name: " SOURCE_FUNCTION_NAME_ARG
fi

readonly SOURCE_FUNCTION_NAME="$SOURCE_FUNCTION_NAME_ARG"
readonly TARGET_DIR="$PERSONAL_MONOREPO_LOCATION/nix/scripts/scripts/$SOURCE_FUNCTION_NAME"

print_debug "Creating directory: $TARGET_DIR"
mkdir -p "$TARGET_DIR"

print_debug "Creating blank file: $TARGET_DIR/source.sh"
touch "$TARGET_DIR/source.sh"

print_status "Created source function '$SOURCE_FUNCTION_NAME' at $TARGET_DIR/source.sh"
