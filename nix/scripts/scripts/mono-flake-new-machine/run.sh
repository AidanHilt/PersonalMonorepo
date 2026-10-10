#!/bin/bash

set -euo pipefail

# @lib: printing-and-output
# @lib: args-and-help
# @lib: env-checks

# Default values
SYSTEM=""
MACHINE_NAME=""

args_description "Create a new machine configuration from the blank-machine template."
args_value "-s" "--system" SYSTEM "SYSTEM" "System type (skips interactive selection)"
args_value "-m" "--machine" MACHINE_NAME "MACHINE" "Machine name (skips interactive input)"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

# Environment variables:
#   PERSONAL_MONOREPO_LOCATION  Path to your personal monorepo

require_monorepo

# Define paths
MACHINES_DIR="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/machines"
TEMPLATE_DIR="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/templates/blank-machine"

# Check if machines directory exists
if [[ ! -d "$MACHINES_DIR" ]]; then
  echo "Error: Machines directory does not exist: $MACHINES_DIR"
  exit 1
fi

# Check if template directory exists
if [[ ! -d "$TEMPLATE_DIR" ]]; then
  echo "Error: Template directory does not exist: $TEMPLATE_DIR"
  exit 1
fi

# Get available systems
mapfile -t SYSTEMS < <(find "$MACHINES_DIR" -maxdepth 1 -type d -exec basename {} \; | grep -v "^machines$" | sort)

if [[ ${#SYSTEMS[@]} -eq 0 ]]; then
  echo "Error: No systems found in $MACHINES_DIR"
  exit 1
fi

# Select system (interactive or from argument)
if [[ -z "$SYSTEM" ]]; then
  echo "Available systems:"
  for i in "${!SYSTEMS[@]}"; do
    echo "$((i + 1)). ${SYSTEMS[i]}"
  done

  while true; do
    read -rp "Select system for new machine (1-${#SYSTEMS[@]}): " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#SYSTEMS[@]} ]]; then
      SYSTEM="${SYSTEMS[$((selection - 1))]}"
      break
    else
      echo "Invalid selection. Please enter a number between 1 and ${#SYSTEMS[@]}."
    fi
  done
else
  # Validate provided system
  if [[ ! " ${SYSTEMS[*]} " == *" $SYSTEM "* ]]; then
    echo "Error: System '$SYSTEM' not found. Available systems:"
    printf '%s\n' "${SYSTEMS[@]}"
    exit 1
  fi
fi

# Get machine name (interactive or from argument)
if [[ -z "$MACHINE_NAME" ]]; then
  while true; do
    read -rp "Enter the name of the machine: " MACHINE_NAME
    if [[ -n "$MACHINE_NAME" ]]; then
      break
    else
      echo "Machine name cannot be empty."
    fi
  done
fi

# Validate machine name (basic validation - no spaces, special chars except hyphens/underscores)
if [[ ! "$MACHINE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: Machine name can only contain letters, numbers, hyphens, and underscores"
  exit 1
fi

# Define destination path
DEST_DIR="$MACHINES_DIR/$SYSTEM/$MACHINE_NAME"

# Check if destination already exists
if [[ -d "$DEST_DIR" ]]; then
  echo "Error: Machine '$MACHINE_NAME' already exists in system '$SYSTEM'"
  echo "Path: $DEST_DIR"
  exit 1
fi

# Create the machine directory
echo "Creating machine '$MACHINE_NAME' for system '$SYSTEM'..."
mkdir -p "$DEST_DIR"

# Copy template files
cp -r "$TEMPLATE_DIR"/configuration.nix "$DEST_DIR"/configuration.nix
mono-flake-template-machine-file-options "$PERSONAL_MONOREPO_LOCATION"/nix/mono-flake/templates/blank-machine/disko.nix "$DEST_DIR"/disko.nix "$PERSONAL_MONOREPO_LOCATION"/nix/mono-flake/modules/shared-disko-configs DISKO_COMMON_CONFIG_OPTIONS
mono-flake-template-machine-file-options "$PERSONAL_MONOREPO_LOCATION"/nix/mono-flake/templates/blank-machine/home.nix "$DEST_DIR"/home.nix "$PERSONAL_MONOREPO_LOCATION"/nix/mono-flake/home-manager/shared-configs HOME_MANAGER_COMMON_CONFIG_OPTIONS
mono-flake-template-machine-file-options "$PERSONAL_MONOREPO_LOCATION"/nix/mono-flake/templates/blank-machine/values.nix "$DEST_DIR"/values.nix "$PERSONAL_MONOREPO_LOCATION"/nix/mono-flake/modules/shared-values VALUES_FILE_COMMON_CONFIG_OPTIONS

sed -i "" 's|../../../modules/shared-values/\(.*\)\.nix$|\1|' "$DEST_DIR"/values.nix

echo "Success! Machine created at: $DEST_DIR"
