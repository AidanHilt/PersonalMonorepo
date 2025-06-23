{ inputs, globals, pkgs, machine-config, ...}:

let
mono-flake-copy-machine = pkgs.writeShellScriptBin "mono-flake-copy-machine" ''
#!/bin/bash

set -euo pipefail

# Default values
SOURCE_MACHINE=""
DESTINATION_MACHINE=""
DESTINATION_SYSTEM=""

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -s, --source SOURCE_MACHINE        Source machine name"
    echo "  -d, --destination DEST_MACHINE     Destination machine name"
    echo "  -t, --target-system SYSTEM         Target system (e.g., x86_64-linux)"
    echo "  -h, --help                         Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  PERSONAL_MONOREPO_LOCATION  Path to your personal monorepo"
    echo ""
    echo "Examples:"
    echo "  $0                                                    # Interactive mode"
    echo "  $0 -s web-server -d web-server-02 -t x86_64-linux   # Non-interactive mode"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--source)
            SOURCE_MACHINE="$2"
            shift 2
            ;;
        -d|--destination)
            DESTINATION_MACHINE="$2"
            shift 2
            ;;
        -t|--target-system)
            DESTINATION_SYSTEM="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check if PERSONAL_MONOREPO_LOCATION is set
if [[ -z "''${PERSONAL_MONOREPO_LOCATION:-}" ]]; then
    echo "Error: PERSONAL_MONOREPO_LOCATION environment variable is not set"
    exit 1
fi

# Define paths
MACHINES_DIR="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/machines"

# Check if machines directory exists
if [[ ! -d "$MACHINES_DIR" ]]; then
    echo "Error: Machines directory does not exist: $MACHINES_DIR"
    exit 1
fi

# Get source machine (interactive or from argument)
if [[ -z "$SOURCE_MACHINE" ]]; then
    # List all machines in subdirectories
    echo "Finding all machines in $MACHINES_DIR..."
    mapfile -t ALL_MACHINE_DIRS < <(find "$MACHINES_DIR" -mindepth 2 -maxdepth 2 -type d | sort)

    if [[ ''${#ALL_MACHINE_DIRS[@]} -eq 0 ]]; then
        echo "Error: No machines found in $MACHINES_DIR"
        exit 1
    fi

    echo "Available machines:"
    for i in "''${!ALL_MACHINE_DIRS[@]}"; do
        MACHINE_PATH="''${ALL_MACHINE_DIRS[i]#$MACHINES_DIR/}"
        echo "$((i+1)). $MACHINE_PATH"
    done

    while true; do
        read -p "Select source machine (1-''${#ALL_MACHINE_DIRS[@]}): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ''${#ALL_MACHINE_DIRS[@]} ]]; then
            SOURCE_DIR="''${ALL_MACHINE_DIRS[$((selection-1))]}"
            SOURCE_MACHINE=$(basename "$SOURCE_DIR")
            break
        else
            echo "Invalid selection. Please enter a number between 1 and ''${#ALL_MACHINE_DIRS[@]}."
        fi
    done

    echo "Selected source machine: $SOURCE_MACHINE"
    echo "Source directory: $SOURCE_DIR"
else
    # Validate source machine name
    if [[ ! "$SOURCE_MACHINE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Source machine name can only contain letters, numbers, hyphens, and underscores"
        exit 1
    fi

    # Find source machine directory
    echo "Searching for source machine '$SOURCE_MACHINE'..."
    SOURCE_DIRS=($(find "$MACHINES_DIR" -type d -name "$SOURCE_MACHINE" 2>/dev/null || true))

    if [[ ''${#SOURCE_DIRS[@]} -eq 0 ]]; then
        echo "Error: Source machine '$SOURCE_MACHINE' not found in $MACHINES_DIR"
        exit 1
    elif [[ ''${#SOURCE_DIRS[@]} -eq 1 ]]; then
        SOURCE_DIR="''${SOURCE_DIRS[0]}"
        echo "Found source machine: $SOURCE_DIR"
    else
        echo "Multiple directories found for source machine '$SOURCE_MACHINE':"
        for i in "''${!SOURCE_DIRS[@]}"; do
            echo "$((i+1)). ''${SOURCE_DIRS[i]#$MACHINES_DIR/}"
        done

        while true; do
            read -p "Select source directory (1-''${#SOURCE_DIRS[@]}): " selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ''${#SOURCE_DIRS[@]} ]]; then
                SOURCE_DIR="''${SOURCE_DIRS[$((selection-1))]}"
                break
            else
                echo "Invalid selection. Please enter a number between 1 and ''${#SOURCE_DIRS[@]}."
            fi
        done
    fi
fi

# Get destination machine name (interactive or from argument)
if [[ -z "$DESTINATION_MACHINE" ]]; then
    while true; do
        read -p "Enter the destination machine name: " DESTINATION_MACHINE
        if [[ -n "$DESTINATION_MACHINE" ]]; then
            break
        else
            echo "Destination machine name cannot be empty."
        fi
    done
fi

# Validate destination machine name
if [[ ! "$DESTINATION_MACHINE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Destination machine name can only contain letters, numbers, hyphens, and underscores"
    exit 1
fi

# Get available systems (directories in machines directory)
mapfile -t SYSTEMS < <(find "$MACHINES_DIR" -maxdepth 1 -type d -exec basename {} \; | grep -v "^machines$" | sort)

if [[ ''${#SYSTEMS[@]} -eq 0 ]]; then
    echo "Error: No systems found in $MACHINES_DIR"
    exit 1
fi

# Select destination system (interactive or from argument)
if [[ -z "$DESTINATION_SYSTEM" ]]; then
    echo "Available systems:"
    for i in "''${!SYSTEMS[@]}"; do
        echo "$((i+1)). ''${SYSTEMS[i]}"
    done

    while true; do
        read -p "Select destination system (1-''${#SYSTEMS[@]}): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ''${#SYSTEMS[@]} ]]; then
            DESTINATION_SYSTEM="''${SYSTEMS[$((selection-1))]}"
            break
        else
            echo "Invalid selection. Please enter a number between 1 and ''${#SYSTEMS[@]}."
        fi
    done
else
    # Validate provided destination system
    if [[ ! " ''${SYSTEMS[*]} " =~ " $DESTINATION_SYSTEM " ]]; then
        echo "Error: System '$DESTINATION_SYSTEM' not found. Available systems:"
        printf '%s\n' "''${SYSTEMS[@]}"
        exit 1
    fi
fi

# Define destination directory
DESTINATION_DIR="$MACHINES_DIR/$DESTINATION_SYSTEM/$DESTINATION_MACHINE"

# Check if destination already exists
if [[ -d "$DESTINATION_DIR" ]]; then
    echo "Warning: Destination directory already exists: $DESTINATION_DIR"
    read -p "Do you want to overwrite it? (y/N): " confirm
    case $confirm in
        [Yy]*)
            echo "Proceeding with overwrite..."
            rm -rf "$DESTINATION_DIR"
            ;;
        *)
            echo "Aborted."
            exit 0
            ;;
    esac
fi

# Create destination directory
echo "Creating destination directory: $DESTINATION_DIR"
mkdir -p "$DESTINATION_DIR"

# Copy files from source to destination
echo "Copying files from $SOURCE_DIR to $DESTINATION_DIR..."

# Check if source directory has files
if [[ ! "$(ls -A "$SOURCE_DIR" 2>/dev/null)" ]]; then
    echo "Warning: Source directory is empty: $SOURCE_DIR"
fi

# Copy all files and directories
cp -r "$SOURCE_DIR"/* "$DESTINATION_DIR/" 2>/dev/null || {
    echo "Warning: No files to copy or copy operation failed"
}

# Verify the copy operation
if [[ -d "$DESTINATION_DIR" ]] && [[ "$(ls -A "$DESTINATION_DIR" 2>/dev/null)" ]]; then
    echo "Success! Machine configuration copied successfully."
else
    echo "Warning: Destination directory created but may be empty."
fi

echo ""
'';
in

{
  environment.systemPackages = [
    mono-flake-copy-machine
  ];
}