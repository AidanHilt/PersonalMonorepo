#!/bin/bash

# @lib: printing-and-output
# @lib: args-and-help
# @lib: env-checks

set -euo pipefail

LIB_NAME_ARG=""

args_description "Create a new lib directory with a lib.sh file from the template"
args_value "" "--lib-name" LIB_NAME_ARG "<name>" "Name of the lib to create (prompted if omitted)"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

require_monorepo

if [[ -z "$LIB_NAME_ARG" ]]; then
  print_debug "No lib name provided, prompting user"
  read -r -p "Enter lib name: " LIB_NAME_ARG
fi

readonly LIB_NAME="$LIB_NAME_ARG"

if [[ ! "$LIB_NAME" =~ ^_?[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  print_error "Invalid lib name '$LIB_NAME': must be lowercase-kebab-case (e.g. my-lib), optionally prefixed with a single leading underscore"
  exit 1
fi

readonly TARGET_DIR="$PERSONAL_MONOREPO_LOCATION/nix/scripts/scripts/$LIB_NAME"

if [[ -e "$TARGET_DIR" ]]; then
  print_error "Target directory already exists: $TARGET_DIR"
  exit 1
fi

print_debug "Creating directory: $TARGET_DIR"
mkdir "$TARGET_DIR"

print_debug "Creating $TARGET_DIR/lib.sh from template"
sed "s/__NAME__/$LIB_NAME/g" "./lib.sh.tmpl" >"$TARGET_DIR/lib.sh"

print_status "Created lib '$LIB_NAME' at $TARGET_DIR/lib.sh"
