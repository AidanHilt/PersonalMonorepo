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
POST_INSTALL_IP_ADDRESS_ARG_PROVIDED=0

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
      IP_ADDRESS="$2"
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
  while true; do
    echo -n "Enter the IP address of the machine you are trying to install NixOS on: "
    read -r IP_ADDRESS

    if ipcalc -c "$POST_INSTALL_IP_ADDRESS" > /dev/null 2>&1; then
      break
    fi

    print_error "Invalid IP address format. Please enter a valid IPv4 address (e.g., 192.168.1.100)"
  done

  print_success "Target IP address: $IP_ADDRESS"
fi

# Confirm before running
echo
print_warning "About to run nixos-anywhere with the following configuration:"
echo "  Machine: $SELECTED_MACHINE"
echo "  Target: root@$IP_ADDRESS"
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

FILES_FOR_NEW_MACHINE=$(generate-homelab-node-files laptop-cluster)

if [[ $NIXOS_ANYWHERE_ARGS_PROVIDED = "true" ]]; then
  read -ra CMD_ARRAY <<< "$NIXOS_ANYWHERE_ARGS"
  nix run github:nix-community/nixos-anywhere -- --flake "$FLAKE_DIR#$SELECTED_MACHINE" --target-host "root@$IP_ADDRESS" --extra-files "$FILES_FOR_NEW_MACHINE" "''${CMD_ARRAY[*]}"
else
  nix run github:nix-community/nixos-anywhere -- --flake "$FLAKE_DIR#$SELECTED_MACHINE" --target-host "root@$IP_ADDRESS" --extra-files "$FILES_FOR_NEW_MACHINE"
fi

if [[ $? -eq 0 ]]; then
  print_success "nixos-anywhere deployment completed successfully!"
else
  print_error "nixos-anywhere deployment failed"
  exit 1
fi

if [[ "$POST_INSTALL_IP_ADDRESS_ARG_PROVIDED" != true ]]; then
  output_message="Enter the IP address of the machine after rebooting: "
  while true; do
    echo -n $output_message
    read -r POST_INSTALL_IP_ADDRESS

    if ipcalc -c "$POST_INSTALL_IP_ADDRESS" > /dev/null 2>&1; then
      break
    fi

    output_message="Invalid IP address format. Please enter a valid IPv4 address (e.g., 192.168.1.100)"
  done
fi

USERNAME=$(get-username-from-machine-name "$SELECTED_MACHINE")

ssh-keygen -R $IP_ADDRESS
ssh -t "$USERNAME@$POST_INSTALL_IP_ADDRESS" "update"

read -p "Is this the first machine of the cluster? (yes/no): " RESPONSE

case "$RESPONSE" in
  [Yy]|[Yy][Ee][Ss])
    echo "Running nixos-kubeconfig-retrieval..."
    nixos-kubeconfig-retrieval $USERNAME $IP_ADDRESS
    ;;
  [Nn]|[Nn][Oo])
    echo "Skipping kubeconfig retrieval for non-first machine."
    ;;
  *)
    echo "Please answer yes or no."
    exit 1
    ;;
esac
'';

kubeconfig-retrieval-script = pkgs.writeShellScriptBin "nixos-kubeconfig-retrieval" ''
#!/bin/bash

set -e

# Function to display usage
usage() {
    echo "Usage: $0 <username> <ip-address> [--cluster-name <name>] [--overwrite-ip <ip>]"
    echo "  username: The username to use for SSH"
    echo "  ip-address: The IP address to use for SSH"
    echo "  --cluster-name: optional cluster name (will prompt if not provided)"
    echo "  --overwrite-ip: optional IP to replace 127.0.0.1 with in the retrieved kubeconfig (uses SSH host IP if not provided)"
    echo ""
    echo "Examples:"
    echo "  $0 root 192.168.1.100"
    echo "  $0 root 192.168.1.100 --cluster-name my-cluster"
    echo "  $0 root 192.168.1.100 --cluster-name prod-cluster --overwrite-ip 10.0.0.100"
    echo "  $0 root 192.168.1.100 --overwrite-ip 10.0.0.100"
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
if [ $# -lt 2 ]; then
    usage
fi

USERNAME="$1"
IP_ADDRESS="$2"
shift
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

# Step 1: Check for RKE2 kubeconfig on remote host
echo "Step 1: Checking for RKE2 kubeconfig on remote host..."

RKE2_CONFIG_PATH="/etc/rancher/rke2/rke2.yaml"
if ! ssh -t "$USERNAME@$IP_ADDRESS" "test -f $RKE2_CONFIG_PATH" 2>/dev/null; then
    echo "Error: RKE2 kubeconfig file does not exist at $RKE2_CONFIG_PATH on remote host"
    exit 1
fi

echo "Found RKE2 kubeconfig, retrieving..."
KUBECONFIG_CONTENT=$(ssh "$USERNAME@$IP_ADDRESS" "sudo cat $RKE2_CONFIG_PATH" 2>/dev/null)

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
REPLACEMENT_IP="$IP_ADDRESS"
if [ "$OVERWRITE_IP" != "" ]; then
    REPLACEMENT_IP="$OVERWRITE_IP"
    echo "Step 4: Replacing 127.0.0.1 with overwrite IP: $REPLACEMENT_IP"
else
    echo "Step 4: Replacing 127.0.0.1 with SSH host IP: $REPLACEMENT_IP"
fi

ESCAPED_IP=$(printf '%s\n' "$REPLACEMENT_IP" | sed 's/[[\.*^$()+?{|]/\\&/g')
KUBECONFIG_CONTENT=$(echo "$KUBECONFIG_CONTENT" | sed "s/127\.0\.0\.1/$ESCAPED_IP/g")

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

# # Clean up temporary file
# rm -f "$TEMP_KUBECONFIG"

sync-kubeconfig

echo ""
echo "Script completed successfully!"
echo "Cluster '$CLUSTER_NAME' has been added to your kubeconfig"
'';

in

{
  imports = [
    ./_kubernetes-admin.nix
    ./_shell-script-lib.nix
  ];

  environment.systemPackages = with pkgs; [
    installer-script
    kubeconfig-retrieval-script

    ipcalc
  ];
}