{ inputs, globals, pkgs, machine-config, lib, ...}:

let

add-import-to-nix = (import ../lib/add-import-to-nix.nix {inherit pkgs;}).add-import-to-nix;
select-directory = (import ../lib/select-directory.nix {inherit pkgs;}).select-directory;

mono-flake-new-bash-function = pkgs.writeShellScriptBin "mono-flake-new-bash-function" ''
#!/bin/bash

set -euo pipefail

source ${add-import-to-nix}
source ${select-directory}

# Default values
FUNCTION_NAME=""

TEMPLATE_FILE="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/templates/bash-function.nix"
OUTPUT_DIR="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/modules/scripts"

# Function to display usage
usage() {
  echo "Usage: $0 [OPTIONS] [FUNCTION_NAME]"
  echo "Options:"
  echo "  -n, --name FUNCTION_NAME   function name (skips interactive input)"
  echo "  -d, --out-dir OUT_DIR    Output dir (skips interactive input)"
  echo "  -s, --script-function  Use a template optimized for scripts
  echo "  -h, --help        Show this help message"
  echo ""
  echo "Environment variables:"
  echo "  PERSONAL_MONOREPO_LOCATION  Path to your personal monorepo"
  echo ""
  echo "Examples:"
  echo "  $0            # Interactive mode"
  echo "  $0 my-function       # Positional argument"
  echo "  $0 -n my-function     # Named argument"
  exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--name)
      FUNCTION_NAME="$2"
      shift 2
      ;;
    -d|--out-dir)
      SELECTED_DIR="$2"
      shift 2
      ;;
    -s|--script-function)
      TEMPLATE_FILE="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/templates/bash-script-function.nix"
      shift 1
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "Unknown option: $1"
      usage
      ;;
    *)
      # Treat as positional argument (function name)
      if [[ -z "$FUNCTION_NAME" ]]; then
        FUNCTION_NAME="$1"
      else
        echo "Error: Multiple function names provided"
        usage
      fi
      shift
      ;;
  esac
done

# Check if PERSONAL_MONOREPO_LOCATION is set
if [[ -z "''${PERSONAL_MONOREPO_LOCATION:-}" ]]; then
  echo "Error: PERSONAL_MONOREPO_LOCATION environment variable is not set"
  exit 1
fi

# Check if template file exists
if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "Error: Template file does not exist: $TEMPLATE_FILE"
  exit 1
fi

# Check if output directory exists, create if not
if [[ ! -d "$OUTPUT_DIR" ]]; then
  echo "Creating output directory: $OUTPUT_DIR"
  mkdir -p "$OUTPUT_DIR"
fi

select_directory

# Get function name (interactive or from argument)
if [[ -z "$FUNCTION_NAME" ]]; then
  while true; do
    read -p "Enter the function name: " FUNCTION_NAME
    if [[ -n "$FUNCTION_NAME" ]]; then
      break
    else
      echo "function name cannot be empty."
    fi
  done
fi

# Validate function name (basic validation - no spaces, special chars except hyphens/underscores)
if [[ ! "$FUNCTION_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: function name can only contain letters, numbers, hyphens, and underscores"
  exit 1
fi

# Add .nix extension if not present
if [[ ! "$FUNCTION_NAME" =~ \.nix$ ]]; then
  FUNCTION_NAME="''${FUNCTION_NAME}.nix"
fi

# Define output file path
OUTPUT_FILE="$OUTPUT_DIR/$selected_dir/$FUNCTION_NAME"

# Check if output file already exists
if [[ -f "$OUTPUT_FILE" ]]; then
  echo "Warning: File '$OUTPUT_FILE' already exists"
  read -p "Do you want to overwrite it? (y/N): " confirm
  case $confirm in
    [Yy]*)
      echo "Overwriting existing file..."
      ;;
    *)
      echo "Aborted."
      exit 0
      ;;
  esac
fi

TARGET_DIR="$(dirname "$OUTPUT_FILE")"
if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Creating directory: $TARGET_DIR"
  mkdir -p "$TARGET_DIR"
fi

# Export the function name as environment variable for envsubst
export FUNCTION_NAME_BASE="''${FUNCTION_NAME%.nix}"  # Remove .nix extension for template use
export FUNCTION_NAME_FULL="$FUNCTION_NAME"

# Check if envsubst is available
if ! command -v envsubst >/dev/null 2>&1; then
  echo "Error: envsubst command not found. Please install gettext package."
  exit 1
fi

# Process template with envsubst
echo "Processing template..."
envsubst < "$TEMPLATE_FILE" > "$OUTPUT_FILE"

if [[ $TEMPLATE_FILE = "$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/templates/bash-function.nix" ]]; then
  add-import-to-nix "$TARGET_DIR/default.nix" "$FUNCTION_NAME_FULL"
fi

echo "Success! function created at: $OUTPUT_FILE"
echo ""
'';

in

{
  environment.systemPackages = [
    mono-flake-new-bash-function
  ];
}