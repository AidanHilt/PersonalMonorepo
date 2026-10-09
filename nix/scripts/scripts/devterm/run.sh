#!/bin/bash

set -euo pipefail

# @lib: printing-and-output
# @lib: args-and-help
IMAGE="aidanhilt/atils-debug:latest"
NAMESPACE=""
COMMAND="zsh"

args_description "Launch a debug pod in a Kubernetes cluster and exec into it."
args_example "$(basename "$0") --image myapp:latest --namespace production --command \"npm start\""
args_value "" "--image" IMAGE "IMAGE" "Docker/container image to use"
args_value "" "--namespace" NAMESPACE "NAMESPACE" "Kubernetes namespace to target"
args_value "" "--command" COMMAND "COMMAND" "Command to execute"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

if [ -z "${NAMESPACE}" ]; then
  NAMESPACE=$(kubectl config view --minify -o jsonpath='{..namespace}')
  if [ -z "${NAMESPACE}" ]; then
    NAMESPACE="default"
  fi
fi

POD_NAME="devterm-${RANDOM}"

print_status "Launching pod ${POD_NAME} in namespace ${NAMESPACE} with image ${IMAGE}"

kubectl run "${POD_NAME}" \
  -n "${NAMESPACE}" \
  --image="${IMAGE}" \
  --restart=Never \
  --command -- sleep infinity 2>/dev/null

print_status "Waiting for pod to be ready"
kubectl wait --for=condition=ready pod/"${POD_NAME}" -n "${NAMESPACE}" --timeout=60s 2>/dev/null

print_status "Executing ${COMMAND} in pod"

kubectl exec -it "${POD_NAME}" -n "${NAMESPACE}" -- "${COMMAND}" || true

print_status "Cleaning up pod ${POD_NAME}"
kubectl delete pod "${POD_NAME}" -n "${NAMESPACE}" --wait=false 2>/dev/null
