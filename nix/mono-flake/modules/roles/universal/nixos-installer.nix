{ inputs, globals, pkgs, machine-config, ...}:

let
installer-script = pkgs.writeShellScriptBin "nixos-remote-install" ''
#!/usr/bin/env bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_error() {
    echo -e "''${RED}Error: $1''${NC}" >&2
}

print_info() {
    echo -e "''${BLUE}Info: $1''${NC}"
}

print_success() {
    echo -e "''${GREEN}Success: $1''${NC}"
}

print_warning() {
    echo -e "''${YELLOW}Warning: $1''${NC}"
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --nixos-anywhere-args ARGS    Arguments to pass through to nixos-anywhere"
    echo "  --help                        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --nixos-anywhere-args '--build-on-remote --debug'"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --nixos-anywhere-args)
            if [[ $# -lt 2 ]]; then
                print_error "--nixos-anywhere-args requires an argument"
                exit 1
            fi
            NIXOS_ANYWHERE_ARGS="$2"
            NIXOS_ANYWHERE_ARGS_PROVIDED=true
            shift 2
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            print_info "Use --help to see available options"
            exit 1
            ;;
        *)
            print_error "Unexpected argument: $1"
            print_info "Currently only --nixos-anywhere-args is supported"
            print_info "Use --help to see usage information"
            exit 1
            ;;
    esac
done

# Check if PERSONAL_MONOREPO_LOCATION is set
if [[ -z "''${PERSONAL_MONOREPO_LOCATION:-}" ]]; then
    print_error "PERSONAL_MONOREPO_LOCATION environment variable is not set"
    print_info "Please set this variable to point to your personal monorepo location"
    exit 1
fi

print_info "Using monorepo location: $PERSONAL_MONOREPO_LOCATION"

# Check if mono-flake directory exists
FLAKE_DIR="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake"
if [[ ! -d "$FLAKE_DIR" ]]; then
    print_error "Directory $FLAKE_DIR does not exist"
    print_info "Please ensure your mono-flake is located at the expected path"
    exit 1
fi

print_success "Found mono-flake directory"

# Collect machine names from both architectures
MACHINES_DIR="$FLAKE_DIR/machines"
MACHINE_NAMES=()

# Check aarch64-linux machines
AARCH64_DIR="$MACHINES_DIR/aarch64-linux"
if [[ -d "$AARCH64_DIR" ]]; then
    for dir in "$AARCH64_DIR"/*/; do
        if [[ -d "$dir" ]]; then
            MACHINE_NAMES+=($(basename "$dir"))
        fi
    done
fi

# Check x86_64-linux machines
X86_64_DIR="$MACHINES_DIR/x86_64-linux"
if [[ -d "$X86_64_DIR" ]]; then
    for dir in "$X86_64_DIR"/*/; do
        if [[ -d "$dir" ]]; then
            MACHINE_NAMES+=($(basename "$dir"))
        fi
    done
fi

# Check if we found any machines
if [[ ''${#MACHINE_NAMES[@]} -eq 0 ]]; then
    print_error "No machine configurations found in $MACHINES_DIR"
    print_info "Please ensure you have machine configurations in aarch64-linux or x86_64-linux subdirectories"
    exit 1
fi

# Sort machine names alphabetically
IFS=$'\n' MACHINE_NAMES=($(sort <<<"''${MACHINE_NAMES[*]}"))
unset IFS

print_success "Found ''${#MACHINE_NAMES[@]} machine configuration(s)"

# Present numbered list to user
echo
print_info "Available machine configurations:"
for ((i=0; i<''${#MACHINE_NAMES[@]}; i++)); do
    echo "  $((i+1))) ''${MACHINE_NAMES[$i]}"
done

# Get user selection
echo
while true; do
    echo -n "Select a machine configuration (1-''${#MACHINE_NAMES[@]}): "
    read -r selection

    # Validate selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ''${#MACHINE_NAMES[@]} ]]; then
        SELECTED_MACHINE="''${MACHINE_NAMES[$((selection-1))]}"
        break
    else
        print_error "Invalid selection. Please enter a number between 1 and ''${#MACHINE_NAMES[@]}"
    fi
done

print_success "Selected machine: $SELECTED_MACHINE"

# Get IP address from user
echo
while true; do
    echo -n "Enter the IP address of the machine you are trying to install NixOS on: "
    read -r ip_address

    # Basic IP validation (IPv4)
    if [[ "$ip_address" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # Check each octet is valid (0-255)
        valid=true
        IFS='.' read -ra ADDR <<< "$ip_address"
        for octet in "''${ADDR[@]}"; do
            if [[ "$octet" -gt 255 ]]; then
                valid=false
                break
            fi
        done

        if $valid; then
            break
        fi
    fi

    print_error "Invalid IP address format. Please enter a valid IPv4 address (e.g., 192.168.1.100)"
done

print_success "Target IP address: $ip_address"

# Confirm before running
echo
print_warning "About to run nixos-anywhere with the following configuration:"
echo "  Machine: $SELECTED_MACHINE"
echo "  Target: root@$ip_address"
echo "  Flake: $FLAKE_DIR#$SELECTED_MACHINE"
echo

echo -n "Continue? (y/N): "
read -r confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_info "Operation cancelled by user"
    exit 0
fi

# Run nixos-anywhere
print_info "Starting nixos-anywhere deployment..."
echo

read -ra CMD_ARRAY <<< "$NIXOS_ANYWHERE_ARGS"


nix run github:nix-community/nixos-anywhere -- --flake "$FLAKE_DIR#$SELECTED_MACHINE" --target-host "root@$ip_address" "${CMD_ARRAY[*]}"

if [[ $? -eq 0 ]]; then
    print_success "nixos-anywhere deployment completed successfully!"
else
    print_error "nixos-anywhere deployment failed"
    exit 1
fi
'';

in

{
  environment.systemPackages = [ installer-script ];
}