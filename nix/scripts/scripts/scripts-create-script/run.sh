#!/bin/bash

# @lib: printing-and-output
# @lib: args-and-help
# @lib: env-checks

set -euo pipefail

SCRIPT_NAME_ARG=""

args_description "Create a new script directory with a blank run.sh file"
args_example "$(basename "$0") --script-name my-script"
args_value "" "--script-name" SCRIPT_NAME_ARG "NAME" "Name of the script to create (prompted if omitted)"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

require_monorepo

if [[ -z "$SCRIPT_NAME_ARG" ]]; then
  print_debug "No script name provided, prompting user"
  read -r -p "Enter script name: " SCRIPT_NAME_ARG
fi

readonly SCRIPT_NAME="$SCRIPT_NAME_ARG"
readonly TARGET_DIR="$PERSONAL_MONOREPO_LOCATION/nix/scripts/scripts/$SCRIPT_NAME"

print_debug "Creating directory: $TARGET_DIR"
mkdir -p "$TARGET_DIR"

print_debug "Creating blank file: $TARGET_DIR/run.sh"
touch "$TARGET_DIR/run.sh"

print_status "Created script '$SCRIPT_NAME' at $TARGET_DIR/run.sh"
