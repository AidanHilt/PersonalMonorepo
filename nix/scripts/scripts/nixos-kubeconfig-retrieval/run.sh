#!/bin/bash

set -euo pipefail

# @lib: printing-and-output
# @lib: args-and-help

# Check if required tools are available
for cmd in ssh sed kubecm; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is not installed or not in PATH"
    exit 1
  fi
done

# Parse arguments
CLUSTER_NAME=""
OVERWRITE_IP=""
USERNAME=""
IP_ADDRESS=""

args_description "Retrieve an RKE2 kubeconfig from a remote host and register it with kubecm."
args_example "$(basename "$0") root 192.168.1.100"
args_example "$(basename "$0") root 192.168.1.100 --cluster-name my-cluster"
args_example "$(basename "$0") root 192.168.1.100 --cluster-name prod-cluster --overwrite-ip 10.0.0.100"
args_example "$(basename "$0") root 192.168.1.100 --overwrite-ip 10.0.0.100"
args_value "" "--cluster-name" CLUSTER_NAME "NAME" "Optional cluster name (will prompt if not provided)"
args_value "" "--overwrite-ip" OVERWRITE_IP "IP" "Optional IP to replace 127.0.0.1 with in the retrieved kubeconfig (uses SSH host IP if not provided)"
args_positional "username" USERNAME "The username to use for SSH" required
args_positional "ip-address" IP_ADDRESS "The IP address to use for SSH" required

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

# Step 1: Check for RKE2 kubeconfig on remote host
echo "Step 1: Checking for RKE2 kubeconfig on remote host..."

RKE2_CONFIG_PATH="/etc/rancher/rke2/rke2.yaml"
if ! ssh -t "$USERNAME@$IP_ADDRESS" "test -f $RKE2_CONFIG_PATH" 2>/dev/null; then
  echo "Error: RKE2 kubeconfig file does not exist at $RKE2_CONFIG_PATH on remote host"
  exit 1
fi

if [ -z "$CLUSTER_NAME" ]; then
  echo ""
  read -rp "Please enter the cluster name: " CLUSTER_NAME
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

ESCAPED_IP=$(printf '%s\n' "$REPLACEMENT_IP" | sed "s/[[\.*^$()+?{|]/\\&/g")
TEMP_KUBECONFIG="/tmp/rke2-kubeconfig-${CLUSTER_NAME}.yaml"

echo "Found RKE2 kubeconfig, retrieving..."
# Note: We actually explicitly WANT to expand on the client side, this is flagging our intended behavior as an issue
# shellcheck disable=SC2029
ssh "$USERNAME@$IP_ADDRESS" "cat $RKE2_CONFIG_PATH" | sed "s/default/$CLUSTER_NAME/g" | sed "s/127\.0\.0\.1/$ESCAPED_IP/g" >"$TEMP_KUBECONFIG"

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
