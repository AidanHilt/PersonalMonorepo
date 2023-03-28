#!/bin/bash

#TODO Create the namespace, and all future namespaces, with sidecar injection label
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd -f "values.yaml" argo/argo-cd -n argocd

for application in applications/*/; do
    kubectl apply -f $application/service.yaml
done