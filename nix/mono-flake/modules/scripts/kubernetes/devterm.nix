{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

devterm = pkgs.writeShellScriptBin "devterm" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}
IMAGE="aidanhilt/atils-debug:latest"
NAMESPACE=""
COMMAND="zsh"

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --image IMAGE        Docker/container image to use
  --namespace NAMESPACE
                       Kubernetes namespace to target
  --command COMMAND    Command to execute
  --help               Display this help message and exit

Example:
  $(basename "$0") --image myapp:latest --namespace production --command "npm start"

EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --image)
      IMAGE="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --command)
      COMMAND="$2"
      shift 2
      ;;
    --help)
      show_help
      exit 0
      ;;
    *)
      print_error "Unknown argument: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

if [ -z "''${NAMESPACE}" ]; then
  NAMESPACE=$(kubectl config view --minify -o jsonpath='{..namespace}')
  if [ -z "''${NAMESPACE}" ]; then
    NAMESPACE="default"
  fi
fi

POD_NAME="devterm-''${RANDOM}"

print_status "Launching pod ''${POD_NAME} in namespace ''${NAMESPACE} with image ''${IMAGE}"

kubectl run "''${POD_NAME}" \
  -n "''${NAMESPACE}" \
  --image="''${IMAGE}" \
  --restart=Never \
  --command -- sleep infinity 2>/dev/null

print_status "Waiting for pod to be ready"
kubectl wait --for=condition=ready pod/"''${POD_NAME}" -n "''${NAMESPACE}" --timeout=60s 2>/dev/null

print_status "Executing ''${COMMAND} in pod"

kubectl exec -it "''${POD_NAME}" -n "''${NAMESPACE}" -- "''${COMMAND}" || true

print_status "Cleaning up pod ''${POD_NAME}"
kubectl delete pod "''${POD_NAME}" -n "''${NAMESPACE}" --wait=false 2>/dev/null
'';
in

{
  environment.systemPackages = [
    devterm
  ];
}