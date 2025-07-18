{ inputs, globals, pkgs, machine-config, ...}:

let

nixos-kubeconfig-retrieval = pkgs.writeShellScriptBin "nixos-kubeconfig-retrieval" ''
#!/bin/bash

set -euo pipefail

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

if [ -z "$CLUSTER_NAME" ]; then
  echo ""
  read -p "Please enter the cluster name: " CLUSTER_NAME
  if [ -z "$CLUSTER_NAME" ]; then
    echo "Error: Cluster name cannot be empty"
    exit 1
  fi
fi

REPLACEMENT_IP="$IP_ADDRESS"
if [ "$OVERWRITE_IP" != "" ]; then
  REPLACEMENT_IP="$OVERWRITE_IP"
  echo "Step 4: Replacing 127.0.0.1 with overwrite IP: $REPLACEMENT_IP"
else
  echo "Step 4: Replacing 127.0.0.1 with SSH host IP: $REPLACEMENT_IP"
fi

ESCAPED_IP=$(printf '%s\n' "$REPLACEMENT_IP" | sed 's/[[\.*^$()+?{|]/\\&/g')
TEMP_KUBECONFIG="/tmp/rke2-kubeconfig-''${CLUSTER_NAME}.yaml"

echo "Found RKE2 kubeconfig, retrieving..."
ssh "$USERNAME@$IP_ADDRESS" "cat $RKE2_CONFIG_PATH" | sed "s/default/$CLUSTER_NAME/g" | sed "s/127\.0\.0\.1/$ESCAPED_IP/g" > "$TEMP_KUBECONFIG"

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
echo "Cluster '$CLUSTER_NAME' has been added to your kubeconfig"
'';

in

{
  imports = [
    # TODO address this, we shouldn't be importing files that start with _.
    ../../roles/universal/kubernetes-admin.nix

    ../lib/default.nix
  ];

  environment.systemPackages = with pkgs; [
    nixos-kubeconfig-retrieval
  ];
}