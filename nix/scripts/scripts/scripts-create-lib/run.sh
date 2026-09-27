#!/bin/bash

# @lib: printing-and-output

set -euo pipefail

show_help () {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Create a new lib directory with a blank lib.sh file"
  echo ""
  echo ""
  echo "OPTIONS:"
  echo "  --lib-name <name>   Name of the lib to create (prompted if omitted)"
  echo "  --help, -h           Show this help message"
}

LIB_NAME_ARG=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --lib-name)
      LIB_NAME_ARG="$2"
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