#!/usr/bin/env bash

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <machine-name>"
  exit 1
fi

MACHINE_NAME="$1"

# Check if PERSONAL_MONOREPO_LOCATION is set
if [ -z "$PERSONAL_MONOREPO_LOCATION" ]; then
  echo "Error: PERSONAL_MONOREPO_LOCATION environment variable is not set"
  exit 1
fi

MONO_FLAKE_PATH="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake"
MACHINES_PATH="$MONO_FLAKE_PATH/machines"

# Step 1: Check for machine folder in both architectures
MACHINE_PATH=""
if [ -d "$MACHINES_PATH/aarch64-linux/$MACHINE_NAME" ]; then
  MACHINE_PATH="$MACHINES_PATH/aarch64-linux/$MACHINE_NAME"
elif [ -d "$MACHINES_PATH/x86_64-linux/$MACHINE_NAME" ]; then
  MACHINE_PATH="$MACHINES_PATH/x86_64-linux/$MACHINE_NAME"
else
  echo "Error: Machine folder '$MACHINE_NAME' not found in aarch64-linux or x86_64-linux"
  exit 1
fi

# Step 2: Check for values.nix file
VALUES_FILE="$MACHINE_PATH/values.nix"
if [ ! -f "$VALUES_FILE" ]; then
  echo "Error: values.nix file not found at $VALUES_FILE"
  exit 1
fi

# Step 3: Extract username from values.nix
# Look for patterns like: username = "value"; or username="value";
USERNAME=$(grep -E '^\s*username\s*=\s*"[^"]*"' "$VALUES_FILE" | sed 's/.*"\([^"]*\)".*/\1/' | head -n1 || true) # Suppress errors if nothing is found

if [ -z "$USERNAME" ]; then
  FILENAME=$(grep -E '^\s*defaultValues\s*=\s*"[^"]*"' "$VALUES_FILE" | sed 's/.*"\([^"]*\)".*/\1/' | head -n1 || true)

  if [ -z "$FILENAME" ]; then
    echo "Could not find username or a default values file. Exiting."
    exit 1
  fi

  DEFAULT_VALUES_FILE="$MONO_FLAKE_PATH/modules/shared-values/$FILENAME.nix"

  USERNAME=$(grep -E '^\s*username\s*=\s*"[^"]*"' "$DEFAULT_VALUES_FILE" | sed 's/.*"\([^"]*\)".*/\1/' | head -n1 || true)
fi

if [ -z "$USERNAME" ]; then
  echo "No username found"
  exit 1
fi

echo "$USERNAME"
