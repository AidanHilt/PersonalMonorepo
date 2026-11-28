# This stores common configuration for running kubernetes. Note that this will not have shell configurations, as we like doing those in Home Manager.
# That configuration is located here:

{
  inputs,
  globals,
  pkgs,
  machine-config,
  config,
  ...
}:

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

  # Cluster name is deliberately fixed to "qa-cluster" (kubeconfig context
  # "kind-qa-cluster") rather than kind's bare default ("kind" / context
  # "kind-kind") -- see nix/agentic-ai-stack/IMPLEMENTERS.md's network
  # model section and terragrunt/qa-cluster's kubeconfig_context inputs,
  # which hardcode "kind-qa-cluster" to match.
  cluster-setup = pkgs.writeShellScriptBin "cluster-setup" ''
    set -euo pipefail

    cat <<EOF | kind create cluster --name qa-cluster --config=-
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

    # After the cluster is up, write an RBAC-scoped kubeconfig pointed at
    # the kind-gateway forwarder sidecar (see
    # nix/agentic-ai-stack/compose.kind.yaml and IMPLEMENTERS.md's network
    # model section) to the agentic-ai-stack's default kubeconfig path,
    # overwriting any previous contents silently -- gen-kubeconfig.sh
    # itself always overwrites $PI_SANDBOX__KUBECONFIG_PATH /
    # ~/.config/pi-sandbox/agent-kubeconfig.yaml.
    if [ -z "''${PERSONAL_MONOREPO_LOCATION:-}" ]; then
      echo "error: PERSONAL_MONOREPO_LOCATION is not set -- cannot locate nix/agentic-ai-stack to generate the pi-sandbox kubeconfig." >&2
      exit 1
    fi

    nix run "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#gen-kubeconfig" -- kind-qa-cluster --yes --server https://kind-gateway:6443 --tls-server-name kubernetes
  '';

  cluster-teardown = pkgs.writeShellScriptBin "cluster-teardown" ''
    kind delete cluster --name qa-cluster
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
    KUBECONFIG_CONTENT=$(cat "$KUBECONFIG")

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

    nix-commit --no-push
    update
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
    jq

    clear-namespace
    cluster-setup
    cluster-teardown
    update-kubeconfig

    # REASON We need to access config, which is not available in the let statement
    # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
    (pkgs.writeShellScriptBin "sync-kubeconfig" ''
      KUBECONFIG=''${KUBECONFIG:-$HOME/.kube/config}
      if [[ ! -d $(dirname $KUBECONFIG) ]]; then
        mkdir $(dirname $KUBECONFIG)
      fi
      cp ${config.age.secrets.kubeconfig.path} $KUBECONFIG
      chmod 600 $KUBECONFIG
    '')
  ];

  age.secrets.kubeconfig = {
    file = ../../../secrets/kubeconfig.age;
    mode = "400";
    owner = "${machine-config.username}";
  };
}
