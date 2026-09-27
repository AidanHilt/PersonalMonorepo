#!/bin/bash

# @lib: printing-and-output

set -euo pipefail

show_help () {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Create a new script directory with a blank run.sh file"
  echo ""
  echo ""
  echo "OPTIONS:"
  echo "  --script-name <name>   Name of the script to create (prompted if omitted)"
  echo "  --help, -h              Show this help message"
}

SCRIPT_NAME_ARG=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --script-name)
      SCRIPT_NAME_ARG="$2"
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