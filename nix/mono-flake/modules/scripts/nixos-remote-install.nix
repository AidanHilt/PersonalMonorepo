{ inputs, globals, pkgs, machine-config, ...}:

let
get-username-from-machine-name = pkgs.writeShellScriptBin "get-username-from-machine-name" ''
#!/usr/bin/env bash

set -euo pipefail

echo "Huh?"

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
USERNAME=$(grep -E '^\s*username\s*=\s*"[^"]*"' "$VALUES_FILE" | sed 's/.*"\([^"]*\)".*/\1/' | head -n1)

FILENAME=$(grep -E '^\s*defaultValues\s*=\s*"[^"]*"' "$VALUES_FILE" | sed 's/.*"\([^"]*\)".*/\1/' | head -n1)
DEFAULT_VALUES_FILE="$MONO_FLAKE_PATH/modules/shared-values/$FILENAME.nix"

if [ -z "$USERNAME" ]; then
  USERNAME=$(grep -E '^\s*defaultValues\s*=\s*"[^"]*"' "$DEFAULT_VALUES_FILE" | sed 's/.*"\([^"]*\)".*/\1/' | head -n1)
fi

if [ -z "$USERNAME" ]; then
  echo "No username found"
  exit 1
fi

echo "$USERNAME"
'';

nixos-remote-install = pkgs.writeShellScriptBin "nixos-remote-install" ''
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
CLUSTER_NAME_ARG_PROVIDED=0

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
  echo "  --machine-name NAME         Name of the machine to use. Must be present in the mono flake"
  echo "  --remote-ip IP              The IP address of the remote machine we want to install NixOS on"
  echo "  --post-install-ip IP        The IP address of the machine after NixOS is installed"
  echo "  --cluster-name CLUSTER_NAME The name of the cluster, used to identify it in kubeconfig and find"
  echo "  --help                      Show this help message"
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
    --post-install-ip)
      if [[ $# -lt 2 ]]; then
        print_error "--post-install-ip requires an argument"
        exit 1
      fi
      POST_INSTALL_IP_ADDRESS="$2"
      POST_INSTALL_IP_ADDRESS_ARG_PROVIDED=true
      shift 2
      ;;
    --cluster-name)
      if [[ $# -lt 2 ]]; then
        print_error "--cluster-name requires an argument"
        exit 1
      fi
      CLUSTER_NAME="$2"
      CLUSTER_NAME_ARG_PROVIDED=true
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

if [[ "$CLUSTER_NAME_ARG_PROVIDED" != true ]]; then
    echo ""
    read -p "Please enter the cluster name: " CLUSTER_NAME
    if [ -z "$CLUSTER_NAME" ]; then
        echo "Error: Cluster name cannot be empty"
        exit 1
    fi
fi

FILES_FOR_NEW_MACHINE=$(generate-homelab-node-files $CLUSTER_NAME)
PUBKEY_LOCATION="$FILES_FOR_NEW_MACHINE/etc/ssh/ssh_host_ed25519_key.pub"

# nixos-key-retrieval "$PUBKEY_LOCATION" "$SELECTED_MACHINE"

# if [[ $NIXOS_ANYWHERE_ARGS_PROVIDED = "true" ]]; then
#   read -ra CMD_ARRAY <<< "$NIXOS_ANYWHERE_ARGS"
#   nix run github:nix-community/nixos-anywhere -- --flake "$FLAKE_DIR#$SELECTED_MACHINE" --target-host "root@$IP_ADDRESS" --extra-files "$FILES_FOR_NEW_MACHINE" "''${CMD_ARRAY[*]}"
# else
#   nix run github:nix-community/nixos-anywhere -- --flake "$FLAKE_DIR#$SELECTED_MACHINE" --target-host "root@$IP_ADDRESS" --extra-files "$FILES_FOR_NEW_MACHINE"
# fi

if [[ $? -eq 0 ]]; then
  print_success "nixos-anywhere deployment completed successfully!"
else
  print_error "nixos-anywhere deployment failed"
  exit 1
fi

if [[ "$POST_INSTALL_IP_ADDRESS_ARG_PROVIDED" = true ]]; then
  termdown 30 --no-bell --title "Waiting for machine to reboot"
else
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

echo "Ok..."

ssh-keygen -R $POST_INSTALL_IP_ADDRESS
ssh-keyscan $POST_INSTALL_IP_ADDRESS >> ~/.ssh/known_hosts

ssh -t "$USERNAME@$POST_INSTALL_IP_ADDRESS" "update"

read -p "Is this the first machine of the cluster? (yes/no): " RESPONSE

case "$RESPONSE" in
  [Yy]|[Yy][Ee][Ss])
    read -p "(Optional) Provide a cluster endpoint to use in the kubeconfig: " ENDPOINT
    echo "Running nixos-kubeconfig-retrieval..."
    if [ -z $ENDPOINT ]; then
      nixos-kubeconfig-retrieval $USERNAME $POST_INSTALL_IP_ADDRESS --cluster-name $CLUSTER_NAME
    else
      nixos-kubeconfig-retrieval $USERNAME $POST_INSTALL_IP_ADDRESS --cluster-name $CLUSTER_NAME --overwrite-ip $ENDPOINT
    fi
    ;;
  *)
    echo "Skipping kubeconfig retrieval for non-first machine."
    ;;
esac
'';
in

{
  environment.systemPackages = with pkgs; [
    ipcalc
    termdown

    nixos-remote-install
    get-username-from-machine-name
  ];
}