{ inputs, globals, pkgs, machine-config, ...}:

let
nixos-hardware-config-retrieval = pkgs.writeShellScriptBin "nixos-hardware-config-retrieval" ''
#!/bin/bash

set -euo pipefail

# Default values
IP_ADDRESS=""
USERNAME=""

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -i, --ip IP_ADDRESS      IP address of the remote machine"
    echo "  -u, --user USERNAME      SSH username"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  PERSONAL_MONOREPO_LOCATION  Path to your personal monorepo"
    echo ""
    echo "Examples:"
    echo "  $0                           # Interactive mode"
    echo "  $0 -i 192.168.1.10 -u root  # Non-interactive mode"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--ip)
            IP_ADDRESS="$2"
            shift 2
            ;;
        -u|--user)
            USERNAME="$2"
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

MACHINES_DIR="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/machines"

if [[ ! -d "$MACHINES_DIR" ]]; then
    echo "Error: Machines directory does not exist: $MACHINES_DIR"
    exit 1
fi

if [[ -z "$IP_ADDRESS" ]]; then
    while true; do
        read -p "Enter the IP address of the remote machine: " IP_ADDRESS
        if [[ -n "$IP_ADDRESS" ]]; then
            # Basic IP validation
            if [[ "$IP_ADDRESS" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                break
            else
                echo "Invalid IP address format. Please try again."
                IP_ADDRESS=""
            fi
        else
            echo "IP address cannot be empty."
        fi
    done
fi

if [[ -z "$USERNAME" ]]; then
    while true; do
        read -p "Enter the SSH username: " USERNAME
        if [[ -n "$USERNAME" ]]; then
            break
        else
            echo "Username cannot be empty."
        fi
    done
fi

# Create temporary directory for hardware config
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# SSH into machine and generate hardware configuration
echo "Generating hardware configuration on remote machine..."
ssh "$USERNAME@$IP_ADDRESS" "nixos-generate-config --show-hardware-config" > "$TEMP_DIR/hardware-configuration.nix"

if [[ ! -s "$TEMP_DIR/hardware-configuration.nix" ]]; then
    echo "Error: Failed to generate or retrieve hardware configuration"
    exit 1
fi

echo "Hardware configuration retrieved successfully!"

# Get hostname from remote machine
echo "Retrieving hostname from remote machine..."
REMOTE_HOSTNAME=$(ssh "$USERNAME@$IP_ADDRESS" "hostname" 2>/dev/null || echo "")

if [[ -z "$REMOTE_HOSTNAME" ]]; then
    echo "Warning: Could not retrieve hostname from remote machine"
else
    echo "Remote hostname: $REMOTE_HOSTNAME"
fi

# Search for hostname directory in machines directory
HOSTNAME_DIR=""
if [[ -n "$REMOTE_HOSTNAME" ]]; then
    echo "Searching for hostname directory in $MACHINES_DIR..."

    # Search recursively for a directory matching the hostname
    FOUND_DIRS=($(find "$MACHINES_DIR" -type d -name "$REMOTE_HOSTNAME" 2>/dev/null || true))

    if [[ ''${#FOUND_DIRS[@]} -eq 1 ]]; then
        HOSTNAME_DIR="''${FOUND_DIRS[0]}"
        echo "Found hostname directory: $HOSTNAME_DIR"
    elif [[ ''${#FOUND_DIRS[@]} -gt 1 ]]; then
        echo "Multiple directories found for hostname '$REMOTE_HOSTNAME':"
        for i in "''${!FOUND_DIRS[@]}"; do
            echo "$((i+1)). ''${FOUND_DIRS[i]}"
        done

        while true; do
            read -p "Select directory (1-''${#FOUND_DIRS[@]}): " selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ''${#FOUND_DIRS[@]} ]]; then
                HOSTNAME_DIR="''${FOUND_DIRS[$((selection-1))]}"
                break
            else
                echo "Invalid selection. Please enter a number between 1 and ''${#FOUND_DIRS[@]}."
            fi
        done
    else
        echo "No directory found for hostname '$REMOTE_HOSTNAME'"
    fi
fi

# If no hostname directory found, ask user for hostname
if [[ -z "$HOSTNAME_DIR" ]]; then
    echo "Available machine directories:"
    mapfile -t ALL_DIRS < <(find "$MACHINES_DIR" -type d -mindepth 2 | sort)

    if [[ ''${#ALL_DIRS[@]} -eq 0 ]]; then
        echo "No machine directories found in $MACHINES_DIR"
        exit 1
    fi

    for i in "''${!ALL_DIRS[@]}"; do
        echo "$((i+1)). ''${ALL_DIRS[i]#$MACHINES_DIR/}"
    done

    while true; do
        read -p "Select target directory for hardware configuration (1-''${#ALL_DIRS[@]}): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ''${#ALL_DIRS[@]} ]]; then
            HOSTNAME_DIR="''${ALL_DIRS[$((selection-1))]}"
            break
        else
            echo "Invalid selection. Please enter a number between 1 and ''${#ALL_DIRS[@]}."
        fi
    done
fi

# Copy hardware configuration to target directory
TARGET_FILE="$HOSTNAME_DIR/hardware-configuration.nix"

# Check if target file already exists
if [[ -f "$TARGET_FILE" ]]; then
    echo "Warning: Hardware configuration already exists at $TARGET_FILE"
    read -p "Do you want to overwrite it? (y/N): " confirm
    case $confirm in
        [Yy]*)
            echo "Overwriting existing hardware configuration..."
            ;;
        *)
            echo "Aborted."
            exit 0
            ;;
    esac
fi

# Copy the hardware configuration
cp "$TEMP_DIR/hardware-configuration.nix" "$TARGET_FILE"

echo "Success! Hardware configuration saved to: $TARGET_FILE"
echo ""
'';
in

{
  environment.systemPackages = [
    nixos-hardware-config-retrieval
  ];
}