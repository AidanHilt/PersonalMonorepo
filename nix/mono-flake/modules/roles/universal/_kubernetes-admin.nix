# This stores common configuration for running kubernetes. Note that this will not have shell configurations, as we like doing those in Home Manager.
# That configuration is located here:

{ inputs, globals, pkgs, machine-config, ...}:

let
  clear-namespace = pkgs.writeShellScriptBin "clear-namespace" ''
  # Get the namespace to delete resources from
  NAMESPACE="$1"

  # Verify that the namespace argument was provided
  if [ -z "$NAMESPACE" ]; then
    echo "Usage: $0 <namespace>"
    exit 1
  fi

  # Verify that the namespace exists
  if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
    echo "Namespace $NAMESPACE does not exist"
    exit 1
  fi

  # Get all resource types available on the cluster
  RESOURCE_TYPES=$(kubectl api-resources --verbs=delete --namespaced=true -o name | sort)

  # Delete all resources in the namespace
  for RESOURCE_TYPE in $RESOURCE_TYPES; do
    kubectl delete --all "$RESOURCE_TYPE" --namespace="$NAMESPACE"
  done
  '';

  cluster-setup = pkgs.writeShellScriptBin "cluster-setup" ''
  cat <<EOF | kind create cluster --config=-
  kind: Cluster
  apiVersion: kind.x-k8s.io/v1alpha4
  nodes:
  - role: control-plane
    kubeadmConfigPatches:
    - |
      kind: InitConfiguration
      nodeRegistration:
        kubeletExtraArgs:
          node-labels: "ingress-ready=true"
    extraPortMappings:
    - containerPort: 80
      hostPort: 80
      protocol: TCP
    - containerPort: 443
      hostPort: 443
      protocol: TCP
  EOF
  '';

  cluster-teardown = pkgs.writeShellScriptBin "cluster-teardown" ''
  kind delete cluster
  '';

  update-kubeconfig = pkgs.writeShellScriptBin "update-kubeconfig" ''
  #!/bin/bash

  set -e

  # Check if required tools are available
  for cmd in yq jq age nix; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
          echo "Error: $cmd is not installed or not in PATH"
          exit 1
      fi
  done

  # Set default kubeconfig path if not set
  if [ -z "$KUBECONFIG" ]; then
      KUBECONFIG="$HOME/.kube/config"
      echo "KUBECONFIG not set, using default: $KUBECONFIG"
  fi

  if [ -z "$PERSONAL_MONOREPO_LOCATION" ]; then
      echo "Error: PERSONAL_MONOREPO_LOCATION environment variable is not set"
      exit 1
  fi

  if [ ! -f "$KUBECONFIG" ]; then
      echo "Error: Kubeconfig file does not exist: $KUBECONFIG"
      exit 1
  fi

  SECRETS_FILE="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/secrets/secrets.nix"
  if [ ! -f "$SECRETS_FILE" ]; then
      echo "Error: secrets.nix file does not exist: $SECRETS_FILE"
      exit 1
  fi

  echo "Step 1: Extracting kubeconfig and stripping current-context..."

  # Step 1: Cat kubeconfig, strip current-context, store the value
  KUBECONFIG_CONTENT=$(cat "$KUBECONFIG" | yq 'del(."current-context")' --yaml-output)

  if [ -z "$KUBECONFIG_CONTENT" ]; then
      echo "Error: Failed to process kubeconfig or result is empty"
      exit 1
  fi

  echo "Successfully processed kubeconfig"

  echo "Step 2: Extracting public keys from secrets.nix..."

  # Step 2: Extract public keys for kubeconfig.age from secrets.nix
  TEMP_RECIPIENTS=$(mktemp)

  # Convert secrets.nix to JSON and extract public keys for kubeconfig.age
  nix eval --json -f "$SECRETS_FILE" | jq -r '.["kubeconfig.age"].publicKeys[]' > "$TEMP_RECIPIENTS"

  # Check if we got any keys
  if [ ! -s "$TEMP_RECIPIENTS" ]; then
      echo "Error: No public keys found for 'kubeconfig.age' in secrets.nix"
      echo "Make sure the key exists and has publicKeys defined"
      rm -f "$TEMP_RECIPIENTS"
      exit 1
  fi

  echo "Found $(wc -l < "$TEMP_RECIPIENTS") public key(s)"

  echo "Step 3: Encrypting kubeconfig with age..."

  # Step 3: Encrypt kubeconfig using age with the recipients file
  OUTPUT_FILE="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/secrets/kubeconfig.age"

  echo "$KUBECONFIG_CONTENT" | age -e -R "$TEMP_RECIPIENTS" > "$OUTPUT_FILE"

  # Clean up temporary file
  rm -f "$TEMP_RECIPIENTS"

  # Verify the output file was created
  if [ -f "$OUTPUT_FILE" ]; then
      echo "Success! Encrypted kubeconfig saved to: $OUTPUT_FILE"
      echo "File size: $(du -h "$OUTPUT_FILE" | cut -f1)"
  else
      echo "Error: Failed to create encrypted kubeconfig file"
      exit 1
  fi

  echo "Script completed successfully!"
'';

in

{
  environment.systemPackages = with pkgs; [
    k9s
    kind
    kubecm
    kubectl
    kubernetes-helm

    # Dependencies for update-kubeconfig
    age
    yq
    jq

    clear-namespace
    cluster-setup
    cluster-teardown
    update-kubeconfig
  ];
}