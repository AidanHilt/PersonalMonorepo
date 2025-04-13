# This stores common configuration for running kubernetes. Note that this will not have shell configurations, as we like doing those in Home Manager.
# That configuration is located here:


{ inputs, pkgs, globals, ... }:

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
  cat ~/.kube/config | pbcopy
  cd ~/PersonalMonorepo/nix/secrets/; agenix -e kubeconfig.age
'';

in

{
  environment.systemPackages = [
    pkgs.k9s
    pkgs.kind
    pkgs.kubecm
    pkgs.kubectl
    pkgs.kubernetes-helm

    clear-namespace
    cluster-setup
    cluster-teardown
    update-kubeconfig
  ];
}