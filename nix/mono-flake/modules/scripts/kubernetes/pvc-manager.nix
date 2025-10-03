{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

pvc-manager = pkgs.writeShellScriptBin "pvc-manager" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

NAMESPACE=""
PVC_NAME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -p|--pvc)
      PVC_NAME="$2"
      shift 2
      ;;
    *)
      print_error "Unknown option: $1"
      print_status "Usage: $0 [-n|--namespace NAMESPACE] [-p|--pvc PVC_NAME]"
      exit 1
      ;;
  esac
done

if [ -z "''$NAMESPACE" ]; then
  CURRENT_NAMESPACE=$(kubectl config view --minify --output 'jsonpath={..namespace}')
  NAMESPACE="''${CURRENT_NAMESPACE:-default}"
fi

if [ -z "''$PVC_NAME" ]; then
  read -p "Enter PVC name: " PVC_NAME
fi

if [ -z "''$PVC_NAME" ]; then
  print_error "PVC name cannot be empty"
  exit 1
fi

print_status "Checking if PVC ''$PVC_NAME exists in namespace ''$NAMESPACE"

if ! kubectl get pvc "''$PVC_NAME" -n "''$NAMESPACE" &>/dev/null; then
  print_error "PVC ''$PVC_NAME not found in namespace ''$NAMESPACE"
  exit 1
fi

print_status "Searching for pods mounting PVC ''$PVC_NAME"

PODS_WITH_PVC=$(kubectl get pods -n "''$NAMESPACE" -o json | jq -r --arg pvc "''$PVC_NAME" '
  .items[] |
  select(.spec.volumes[]?.persistentVolumeClaim.claimName == $pvc) |
  .metadata.name
')

if [ -n "$PODS_WITH_PVC" ]; then
  POD_NAME=$(echo "$PODS_WITH_PVC" | head -n 1)
  print_status "Found pod $POD_NAME mounting PVC, attaching ephemeral debug container"

  EPHEMERAL_CONTAINER_NAME="pvc-manager-$(date)"

  VOLUME_NAME=$(kubectl get pod "''$POD_NAME" -n "''$NAMESPACE" -o json | jq -r --arg pvc "''$PVC_NAME" '
    .spec.volumes[] |
    select(.persistentVolumeClaim.claimName == $pvc) |
    .name
  ' | head -n 1)

  kubectl patch pod "''$POD_NAME" -n "''$NAMESPACE" --subresource=ephemeralcontainers --type=strategic -p "{
    \"spec\": {
      \"ephemeralContainers\": [{
        \"name\": \"''$EPHEMERAL_CONTAINER_NAME\",
        \"image\": \"busybox\",
        \"command\": [\"sleep\", \"infinity\"],
        \"stdin\": true,
        \"tty\": true,
        \"volumeMounts\": [{
          \"name\": \"''$VOLUME_NAME\",
          \"mountPath\": \"/pvc\"
        }]
      }]
    }
  }"

  print_status "Waiting for ephemeral container to be ready"
  sleep 2

  kubectl exec -n "''$NAMESPACE" -it "''$POD_NAME" -c "''$EPHEMERAL_CONTAINER_NAME" -- sh
else
  print_status "No pods found mounting PVC, creating debug pod"

  DEBUG_POD_NAME="debug-pvc-''${PVC_NAME}-''${RANDOM}"

  kubectl run "''$DEBUG_POD_NAME" -n "''$NAMESPACE" \
    --image=busybox \
    --restart=Never \
    --overrides="{
      \"spec\": {
        \"containers\": [{
          \"name\": \"debug\",
          \"image\": \"busybox\",
          \"command\": [\"sleep\", \"3600\"],
          \"volumeMounts\": [{
            \"name\": \"pvc\",
            \"mountPath\": \"/pvc\"
          }]
        }],
        \"volumes\": [{
          \"name\": \"pvc\",
          \"persistentVolumeClaim\": {
            \"claimName\": \"''$PVC_NAME\"
          }
        }]
      }
    }" \
    --command -- sleep 3600

  print_status "Waiting for debug pod to be ready"
  kubectl wait --for=condition=ready pod/"''$DEBUG_POD_NAME" -n "''$NAMESPACE" --timeout=60s

  print_status "Execing into debug pod"
  kubectl exec -n "''$NAMESPACE" -it "''$DEBUG_POD_NAME" -- sh

  print_status "Cleaning up debug pod"
  kubectl delete pod "''$DEBUG_POD_NAME" -n "''$NAMESPACE"
fi
'';
in

{
  environment.systemPackages = [
    pvc-manager
  ];
}