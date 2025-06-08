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

# False by default
NIXOS_ANYWHERE_ARGS_PROVIDED=0
SELECTED_MACHINE_ARG_PROVIDED=0
IP_ADDRESS_ARG_PROVIDED=0

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
  echo "  --nixos-anywhere-args ARGS  Arguments to pass through to nixos-anywhere"
  echo "  --machine-name NAME  Name of the machine to use. Must be present in the mono flake"
  echo "  --remote-ip IP  The IP address of the remote machine we want to install NixOS on"
  echo "  --help            Show this help message"
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
    --machine-name)
      if [[ $# -lt 2 ]]; then
        print_error "--machine-name requires an argument"
        exit 1
      fi
      SELECTED_MACHINE="$2"
      SELECTED_MACHINE_ARG_PROVIDED=true
      shift 2
      ;;
    --remote-ip)
      if [[ $# -lt 2 ]]; then
        print_error "--remote-ip requires an argument"
        exit 1
      fi
      ip_address="$2"
      IP_ADDRESS_ARG_PROVIDED=true
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

if [[ "$SELECTED_MACHINE_ARG_PROVIDED" != true ]]; then
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
fi

if [[ "$IP_ADDRESS_ARG_PROVIDED" != true ]]; then
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
fi

# Confirm before running
echo
print_warning "About to run nixos-anywhere with the following configuration:"
echo "  Machine: $SELECTED_MACHINE"
echo "  Target: root@$ip_address"
echo "  Flake: $FLAKE_DIR#$SELECTED_MACHINE"
echo

echo -n "Continue? (Y/n): "
read -r confirm

if [[ "$confirm" =~ ^[Nn]$ ]]; then
  print_info "Operation cancelled by user"
  exit 0
fi

# Run nixos-anywhere
print_info "Starting nixos-anywhere deployment..."
echo

if [[ $NIXOS_ANYWHERE_ARGS_PROVIDED = "true" ]]; then
  read -ra CMD_ARRAY <<< "$NIXOS_ANYWHERE_ARGS"
  nix run github:nix-community/nixos-anywhere -- --flake "$FLAKE_DIR#$SELECTED_MACHINE" --target-host "root@$ip_address" "''${CMD_ARRAY[*]}"
else
  nix run github:nix-community/nixos-anywhere -- --flake "$FLAKE_DIR#$SELECTED_MACHINE" --target-host "root@$ip_address"
fi

if [[ $? -eq 0 ]]; then
  print_success "nixos-anywhere deployment completed successfully!"
else
  print_error "nixos-anywhere deployment failed"
  exit 1
fi

# Get IP address from user
echo
while true; do
  echo -n "Enter the IP address of the machine after rebooting: "
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
done

nixos-key-retrieval $SELECTED_MACHINE $ip_address
'';

ssh-key-retrieval-script = pkgs.writeShellScriptBin "nixos-key-retrieval" ''
#!/bin/bash

set -e

# Check if required arguments are provided
if [ $# -ne 2 ]; then
  echo "Usage: $0 <machine-name> <ip-address>"
  exit 1
fi

MACHINE_NAME="$1"
IP_ADDRESS="$2"

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

echo "Found machine at: $MACHINE_PATH"

# Step 2: Check for values.nix file
VALUES_FILE="$MACHINE_PATH/values.nix"
if [ ! -f "$VALUES_FILE" ]; then
  echo "Error: values.nix file not found at $VALUES_FILE"
  exit 1
fi

echo "Found values.nix file"

# Step 3: Extract username from values.nix
# Look for patterns like: username = "value"; or username="value";
USERNAME=$(grep -E '^\s*username\s*=\s*"[^"]*"' "$VALUES_FILE" | sed 's/.*"\([^"]*\)".*/\1/' | head -n1)

if [ -z "$USERNAME" ]; then
  echo "Error: Could not find username in $VALUES_FILE"
  echo "Looking for pattern: username = \"value\";"
  exit 1
fi

echo "Found username: $USERNAME"

# Step 4: SSH and get public key
echo "Connecting to $USERNAME@$IP_ADDRESS to retrieve SSH public key..."
SSH_PUBKEY=$(ssh "$USERNAME@$IP_ADDRESS" "cat /etc/ssh/ssh_host_ed25519_key.pub" 2>/dev/null)

if [ -z "$SSH_PUBKEY" ]; then
  echo "Error: Could not retrieve SSH public key from $USERNAME@$IP_ADDRESS"
  echo "Make sure ~/.ssh/id_ed25519.pub exists on the remote machine"
  exit 1
fi

echo "Retrieved SSH public key"

# Step 5: Create the formatted string
FORMATTED_STRING="''${MACHINE_NAME}-system = \"$SSH_PUBKEY\";"
echo "Generated string: $FORMATTED_STRING"

# Step 6: Copy to clipboard
# Try different clipboard commands based on what's available
if command -v pbcopy >/dev/null 2>&1; then
  # macOS
  echo "$FORMATTED_STRING" | pbcopy
  echo "Copied to clipboard using pbcopy"
elif command -v xclip >/dev/null 2>&1; then
  # Linux with xclip
  echo "$FORMATTED_STRING" | xclip -selection clipboard
  echo "Copied to clipboard using xclip"
elif command -v wl-copy >/dev/null 2>&1; then
  # Wayland
  echo "$FORMATTED_STRING" | wl-copy
  echo "Copied to clipboard using wl-copy"
else
  echo "Warning: No clipboard utility found (pbcopy, xclip, wl-copy)"
  echo "The formatted string is: $FORMATTED_STRING"
fi

# Step 7: Open secrets.nix
SECRETS_FILE="$MONO_FLAKE_PATH/secrets/secrets.nix"
echo "Opening $SECRETS_FILE..."

# Try different editors based on what's available and environment
if [ -n "$EDITOR" ]; then
  $EDITOR "$SECRETS_FILE"
elif command -v code >/dev/null 2>&1; then
  code "$SECRETS_FILE"
elif command -v vim >/dev/null 2>&1; then
  vim "$SECRETS_FILE"
elif command -v nano >/dev/null 2>&1; then
  nano "$SECRETS_FILE"
else
  echo "Warning: No suitable editor found. Please manually edit: $SECRETS_FILE"
  echo "Add this line: $FORMATTED_STRING"
fi

# Step 8: Change to secrets directory and run agenix
SECRETS_DIR="$MONO_FLAKE_PATH/secrets"
echo "Changing to $SECRETS_DIR and running agenix -e..."
cd "$SECRETS_DIR"

if command -v agenix >/dev/null 2>&1; then
  agenix -r
else
  echo "Error: agenix command not found in PATH"
  echo "Make sure agenix is installed and available"
  exit 1
fi

echo "Script completed successfully!"
'';

kubeconfig-retrieval-script = pkgs.writeShellScriptBin "nixos-kubeconfig-retrieval" ''
#!/bin/bash

set -e

# Function to display usage
usage() {
    echo "Usage: $0 <ssh-connection-string> [--cluster-name <name>] [--overwrite-ip <ip>]"
    echo "  ssh-connection-string: user@host format"
    echo "  --cluster-name: optional cluster name (will prompt if not provided)"
    echo "  --overwrite-ip: optional IP to replace 127.0.0.1 (uses SSH host IP if not provided)"
    echo ""
    echo "Examples:"
    echo "  $0 root@192.168.1.100"
    echo "  $0 root@192.168.1.100 --cluster-name my-cluster"
    echo "  $0 root@192.168.1.100 --cluster-name prod-cluster --overwrite-ip 10.0.0.100"
    echo "  $0 root@192.168.1.100 --overwrite-ip 10.0.0.100"
    exit 1
}

# Check if required tools are available
for cmd in ssh sed kubecm; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd is not installed or not in PATH"
        exit 1
    fi
done

# Parse arguments
SSH_CONNECTION=""
CLUSTER_NAME=""
OVERWRITE_IP=""

# First argument must be SSH connection string
if [ $# -lt 1 ]; then
    usage
fi

SSH_CONNECTION="$1"
shift

# Parse optional arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-name)
            if [ -n "$2" ] && [[ $2 != --* ]]; then
                CLUSTER_NAME="$2"
                shift 2
            else
                echo "Error: --cluster-name requires a value"
                usage
            fi
            ;;
        --overwrite-ip)
            if [ -n "$2" ] && [[ $2 != --* ]]; then
                OVERWRITE_IP="$2"
                shift 2
            else
                echo "Error: --overwrite-ip requires a value"
                usage
            fi
            ;;
        *)
            echo "Error: Unknown option $1"
            usage
            ;;
    esac
done

# Validate SSH connection string format
if [[ ! "$SSH_CONNECTION" =~ .+@.+ ]]; then
    echo "Error: Invalid SSH connection string format. Expected: user@host"
    usage
fi

# Extract IP from SSH connection string
SSH_HOST_IP=$(echo "$SSH_CONNECTION" | sed 's/.*@//')

echo "SSH Connection: $SSH_CONNECTION"
echo "SSH Host IP: $SSH_HOST_IP"

# Step 1: Check for RKE2 kubeconfig on remote host
echo "Step 1: Checking for RKE2 kubeconfig on remote host..."

RKE2_CONFIG_PATH="/etc/rancher/rke2/rke2.yaml"
if ! ssh "$SSH_CONNECTION" "test -f $RKE2_CONFIG_PATH" 2>/dev/null; then
    echo "Error: RKE2 kubeconfig file does not exist at $RKE2_CONFIG_PATH on remote host"
    exit 1
fi

echo "Found RKE2 kubeconfig, retrieving..."
KUBECONFIG_CONTENT=$(ssh "$SSH_CONNECTION" "cat $RKE2_CONFIG_PATH" 2>/dev/null)

if [ -z "$KUBECONFIG_CONTENT" ]; then
    echo "Error: Failed to retrieve kubeconfig content or file is empty"
    exit 1
fi

echo "Successfully retrieved kubeconfig content"

# Step 2: Get cluster name if not provided
if [ -z "$CLUSTER_NAME" ]; then
    echo ""
    read -p "Please enter the cluster name: " CLUSTER_NAME
    if [ -z "$CLUSTER_NAME" ]; then
        echo "Error: Cluster name cannot be empty"
        exit 1
    fi
fi

echo "Using cluster name: $CLUSTER_NAME"

# Step 3: Replace all occurrences of "default" with cluster name
echo "Step 3: Replacing 'default' with '$CLUSTER_NAME'..."
KUBECONFIG_CONTENT=$(echo "$KUBECONFIG_CONTENT" | sed "s/default/$CLUSTER_NAME/g")

# Step 4: Replace 127.0.0.1 with appropriate IP
REPLACEMENT_IP="$SSH_HOST_IP"
if [ -n "$OVERWRITE_IP" ]; then
    REPLACEMENT_IP="$OVERWRITE_IP"
    echo "Step 4: Replacing 127.0.0.1 with overwrite IP: $REPLACEMENT_IP"
else
    echo "Step 4: Replacing 127.0.0.1 with SSH host IP: $REPLACEMENT_IP"
fi

KUBECONFIG_CONTENT=$(echo "$KUBECONFIG_CONTENT" | sed "s/127\.0\.0\.1/$REPLACEMENT_IP/g")

# Step 5: Output edited YAML to file
TEMP_KUBECONFIG="/tmp/rke2-kubeconfig-''${CLUSTER_NAME}.yaml"
echo "$KUBECONFIG_CONTENT" > "$TEMP_KUBECONFIG"

echo "Step 5: Saved edited kubeconfig to: $TEMP_KUBECONFIG"

# Step 6: Use kubecm to add the kubeconfig
echo "Step 6: Adding kubeconfig to primary kubeconfig using kubecm..."

if ! kubecm add -f "$TEMP_KUBECONFIG" --context-name "$CLUSTER_NAME"; then
    echo "Error: Failed to add kubeconfig using kubecm"
    echo "Temporary kubeconfig saved at: $TEMP_KUBECONFIG"
    exit 1
fi

echo "Successfully added kubeconfig context: $CLUSTER_NAME"

# Step 7: Call update-kubeconfig script
echo "Step 7: Running update-kubeconfig script..."

if command -v update-kubeconfig >/dev/null 2>&1; then
    if ! update-kubeconfig; then
        echo "Warning: update-kubeconfig script failed, but kubeconfig was still added"
    else
        echo "Successfully ran update-kubeconfig"
    fi
else
    echo "Warning: update-kubeconfig script not found in PATH"
    echo "You may need to run it manually if required"
fi

# Clean up temporary file
rm -f "$TEMP_KUBECONFIG"

echo ""
echo "Script completed successfully!"
echo "Cluster '$CLUSTER_NAME' has been added to your kubeconfig"
echo "You can now use: kubectl config use-context $CLUSTER_NAME"
'';

in

{
  imports = [ ./_kubernetes-admin.nix ];

  environment.systemPackages = [
    installer-script
    ssh-key-retrieval-script
    kubeconfig-retrieval-script
  ];
}