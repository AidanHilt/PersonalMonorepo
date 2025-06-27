{ inputs, globals, pkgs, machine-config, ...}:

let
mono-flake-template-machine-file-options = pkgs.writeShellScriptBin "mono-flake-template-machine-file-options" ''
#!/bin/bash

set -euo pipefail
# Check if correct number of arguments provided
if [ $# -ne 4 ]; then
  echo "Usage: $0 <source_file> <destination_file> <options_file_path> <target_variable>" >&2
  exit 1
fi

SOURCE_FILE="$1"
DESTINATION_FILE="$2"
OPTIONS_PATH="$3"
TARGET_VARIABLE="$4"

# Validate source file exists
if [ ! -f "$SOURCE_FILE" ]; then
  echo "Error: Source file '$SOURCE_FILE' does not exist" >&2
  exit 1
fi

# Validate options path exists
if [ ! -d "$OPTIONS_PATH" ]; then
  echo "Error: Options path '$OPTIONS_PATH' does not exist or is not a directory" >&2
  exit 1
fi

# Create destination directory if it doesn't exist
DEST_DIR=$(dirname "$DESTINATION_FILE")
if [ ! -d "$DEST_DIR" ]; then
  mkdir -p "$DEST_DIR"
fi

# Step 2 & 3: Create newline-separated list of files with prepended/appended newlines
# with relative paths from destination to options files
FILE_LIST=""
FILE_LIST+="\n"  # Prepend newline

# Get destination directory for relative path calculation
DEST_DIR=$(dirname "$DESTINATION_FILE")

get_relative_path() {
  local target="$1"
  local base="$2"

  # Use Python to calculate relative path
  python3 -c "import os.path; print(os.path.relpath('$target', '$base'))" 2>/dev/null
}

# Get all files in the options directory (not subdirectories)
for file in "$OPTIONS_PATH"/*; do
  if [ -f "$file" ]; then
    # Calculate relative path from destination directory to the options file
    relative_path=$(get_relative_path "$DEST_DIR" "$file")

    if [ -n "$FILE_LIST" ] && [ "$FILE_LIST" != "\n" ]; then
      FILE_LIST+="\n    #$relative_path"
    else
      FILE_LIST+="    #$relative_path"
    fi
  fi
done

FILE_LIST+="\n  "  # Append newline

# Step 3: Export the target variable with the file list
export "$TARGET_VARIABLE"="$FILE_LIST"

# Step 4: Run envsubst on source file and copy result to destination
envsubst < "$SOURCE_FILE" > "$DESTINATION_FILE"

echo "Successfully processed '$SOURCE_FILE' -> '$DESTINATION_FILE'"
'';
in

{
  environment.systemPackages = with pkgs; [
    mono-flake-template-machine-file-options

    python3
  ];
}