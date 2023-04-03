#!/bin/bash

#TODO Create the namespace, and all future namespaces, with sidecar injection label
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd -f "values.yaml" argo/argo-cd -n argocd

kubectl apply -f applications/klonghorn/service.yaml

for application in applications/*; do
  if [[ -d "$application" && "${application##*/}" != "longhorn" ]]; then
    kubectl apply -f $application/service.yaml
  fi
done

namespaces=($(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'))

# Loop over each namespace and add the ArgoCD injection annotation
for ns in "${namespaces[@]}"; do
  kubectl label namespace "$ns" "istio-injection=enabled"
done
