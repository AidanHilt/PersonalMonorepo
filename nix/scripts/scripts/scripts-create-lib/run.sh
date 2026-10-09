#!/bin/bash

# @lib: printing-and-output
# @lib: args-and-help

set -euo pipefail

LIB_NAME_ARG=""

args_description "Create a new lib directory with a blank lib.sh file"
args_value "" "--lib-name" LIB_NAME_ARG "<name>" "Name of the lib to create (prompted if omitted)"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

: "${PERSONAL_MONOREPO_LOCATION:?PERSONAL_MONOREPO_LOCATION must be set}"

if [[ -z "$LIB_NAME_ARG" ]]; then
  print_debug "No lib name provided, prompting user"
  read -r -p "Enter lib name: " LIB_NAME_ARG
fi

readonly LIB_NAME="$LIB_NAME_ARG"
readonly TARGET_DIR="$PERSONAL_MONOREPO_LOCATION/nix/scripts/scripts/$LIB_NAME"

print_debug "Creating directory: $TARGET_DIR"
mkdir -p "$TARGET_DIR"

print_debug "Creating blank file: $TARGET_DIR/lib.sh"
touch "$TARGET_DIR/lib.sh"

print_status "Created lib '$LIB_NAME' at $TARGET_DIR/lib.sh"
