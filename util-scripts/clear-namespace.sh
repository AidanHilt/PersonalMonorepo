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

# Delete all resources in the namespace
kubectl delete all --all -n "$NAMESPACE" --grace-period 0 --force

# Delete any remaining resources in the namespace (e.g. ConfigMaps, Secrets, PersistentVolumeClaims, etc.)
kubectl delete --all configmaps,secrets,persistentvolumeclaims,roles,rolebindings --namespace "$NAMESPACE"
