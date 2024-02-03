#!/bin/bash

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