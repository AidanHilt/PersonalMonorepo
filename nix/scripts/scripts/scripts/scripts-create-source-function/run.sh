#!/bin/bash

# @lib: printing-and-output
# @lib: args-and-help
# @lib: env-checks

set -euo pipefail

SOURCE_FUNCTION_NAME_ARG=""

args_description "Create a new source function directory with a source.sh file from the template"
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

if [[ ! "$SOURCE_FUNCTION_NAME" =~ ^_?[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  print_error "Invalid source function name '$SOURCE_FUNCTION_NAME': must be lowercase-kebab-case (e.g. my-function), optionally prefixed with a single leading underscore"
  exit 1
fi

readonly TARGET_DIR="$PERSONAL_MONOREPO_LOCATION/nix/scripts/scripts/$SOURCE_FUNCTION_NAME"

if [[ -e "$TARGET_DIR" ]]; then
  print_error "Target directory already exists: $TARGET_DIR"
  exit 1
fi

print_debug "Creating directory: $TARGET_DIR"
mkdir "$TARGET_DIR"

print_debug "Creating $TARGET_DIR/source.sh from template"
sed "s/__NAME__/$SOURCE_FUNCTION_NAME/g" "./source.sh.tmpl" >"$TARGET_DIR/source.sh"

print_status "Created source function '$SOURCE_FUNCTION_NAME' at $TARGET_DIR/source.sh"
