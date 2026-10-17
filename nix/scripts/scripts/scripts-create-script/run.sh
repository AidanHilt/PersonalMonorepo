#!/bin/bash

# @lib: printing-and-output
# @lib: args-and-help
# @lib: env-checks

set -euo pipefail

SCRIPT_NAME_ARG=""

args_description "Create a new script directory with a run.sh file from the template"
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

if [[ ! "$SCRIPT_NAME" =~ ^_?[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  print_error "Invalid script name '$SCRIPT_NAME': must be lowercase-kebab-case (e.g. my-script), optionally prefixed with a single leading underscore"
  exit 1
fi

readonly TARGET_DIR="$PERSONAL_MONOREPO_LOCATION/nix/scripts/scripts/$SCRIPT_NAME"

if [[ -e "$TARGET_DIR" ]]; then
  print_error "Target directory already exists: $TARGET_DIR"
  exit 1
fi

print_debug "Creating directory: $TARGET_DIR"
mkdir "$TARGET_DIR"

print_debug "Creating $TARGET_DIR/run.sh from template"
sed "s/__NAME__/$SCRIPT_NAME/g" "./run.sh.tmpl" >"$TARGET_DIR/run.sh"

print_status "Created script '$SCRIPT_NAME' at $TARGET_DIR/run.sh"
