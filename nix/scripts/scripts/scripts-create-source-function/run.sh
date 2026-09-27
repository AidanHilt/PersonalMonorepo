#!/bin/bash

# @lib: printing-and-output

set -euo pipefail

show_help () {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Create a new source function directory with a blank source.sh file"
  echo ""
  echo ""
  echo "OPTIONS:"
  echo "  --source-function-name <name>   Name of the source function to create (prompted if omitted)"
  echo "  --help, -h                        Show this help message"
}

SOURCE_FUNCTION_NAME_ARG=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --source-function-name)
      SOURCE_FUNCTION_NAME_ARG="$2"
      shift 2
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      print_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

: "${PERSONAL_MONOREPO_LOCATION:?PERSONAL_MONOREPO_LOCATION must be set}"

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