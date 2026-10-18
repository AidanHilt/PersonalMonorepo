#!/bin/bash

# @lib: printing-and-output
# @lib: args-and-help
# @lib: env-checks

set -euo pipefail

LIB_NAME_ARG=""
GROUP_ARG=""

args_description "Create a new lib directory with a lib.sh file from the template"
args_example "$(basename "$0") --lib-name my-lib"
args_value "" "--lib-name" LIB_NAME_ARG "<name>" "Name of the lib to create (prompted if omitted)"
args_value "" "--group" GROUP_ARG "GROUP" "Group directory to create the lib under (scripts/<group>/<name>); created if absent. Only use this when the lib's name shares the group's prefix -- otherwise it belongs in scripts/libs/"

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
  readonly TARGET_DIR="$SCRIPTS_ROOT/$GROUP_ARG/$LIB_NAME"
else
  readonly TARGET_DIR="$SCRIPTS_ROOT/$LIB_NAME"
fi

# Global uniqueness: the name must not already exist anywhere under
# scripts/ (top level or inside any group) and must not equal an existing
# group name.
EXISTING_MATCH="$(find "$SCRIPTS_ROOT" -mindepth 1 -maxdepth 2 -type d -name "$LIB_NAME" 2>/dev/null | head -n1)"
if [[ -n "$EXISTING_MATCH" ]]; then
  print_error "'$LIB_NAME' already exists under scripts/: $EXISTING_MATCH"
  exit 1
fi

print_debug "Creating directory: $TARGET_DIR"
mkdir -p "$TARGET_DIR"

print_debug "Creating $TARGET_DIR/lib.sh from template"
sed "s/__NAME__/$LIB_NAME/g" "./lib.sh.tmpl" >"$TARGET_DIR/lib.sh"

print_status "Created lib '$LIB_NAME' at $TARGET_DIR/lib.sh"
