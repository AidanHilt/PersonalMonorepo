#!/bin/bash

#include printing-and-output
#include args-and-help
#include env-checks

set -euo pipefail

SOURCE_FUNCTION_NAME_ARG=""
GROUP_ARG=""

args_description "Create a new source function directory with a source.sh file from the template"
args_example "$(basename "$0") --source-function-name my-function"
args_example "$(basename "$0") --source-function-name my-function --group my-group"
args_value "" "--source-function-name" SOURCE_FUNCTION_NAME_ARG "NAME" "Name of the source function to create (prompted if omitted)"
args_value "" "--group" GROUP_ARG "GROUP" "Group directory to create the source function under (scripts/<group>/<name>); created if absent. Omit for a top-level source function"

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

readonly SCRIPTS_ROOT="$PERSONAL_MONOREPO_LOCATION/nix/scripts/scripts"

if [[ -n "$GROUP_ARG" ]]; then
  if [[ ! "$GROUP_ARG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    print_error "Invalid group name '$GROUP_ARG': must be lowercase-kebab-case (e.g. my-group)"
    exit 1
  fi
  for marker in go.mod run.sh lib.sh source.sh; do
    if [[ -e "$SCRIPTS_ROOT/$GROUP_ARG/$marker" ]]; then
      print_error "'$GROUP_ARG' already exists as a script, not a group: $SCRIPTS_ROOT/$GROUP_ARG"
      exit 1
    fi
  done
  readonly TARGET_DIR="$SCRIPTS_ROOT/$GROUP_ARG/$SOURCE_FUNCTION_NAME"
else
  readonly TARGET_DIR="$SCRIPTS_ROOT/$SOURCE_FUNCTION_NAME"
fi

# Global uniqueness: the name must not already exist anywhere under
# scripts/ (top level or inside any group) and must not equal an existing
# group name.
EXISTING_MATCH="$(find "$SCRIPTS_ROOT" -mindepth 1 -maxdepth 2 -type d -name "$SOURCE_FUNCTION_NAME" 2>/dev/null | head -n1)"
if [[ -n "$EXISTING_MATCH" ]]; then
  print_error "'$SOURCE_FUNCTION_NAME' already exists under scripts/: $EXISTING_MATCH"
  exit 1
fi

print_debug "Creating directory: $TARGET_DIR"
mkdir -p "$TARGET_DIR"

print_debug "Creating $TARGET_DIR/source.sh from template"
sed "s/__NAME__/$SOURCE_FUNCTION_NAME/g" "./source.sh.tmpl" >"$TARGET_DIR/source.sh"

print_status "Created source function '$SOURCE_FUNCTION_NAME' at $TARGET_DIR/source.sh"
