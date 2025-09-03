{ inputs, globals, pkgs, machine-config, lib, ...}:

let
argocd-create-master-stack = pkgs.writeShellScriptBin "argocd-create-master-stack" ''
#!/bin/bash

set -euo pipefail

if [[ ! -v MONOREPO_BRANCH ]]; then
  if [[ -v PERSONAL_MONOREPO_LOCATION ]]; then
    export MONOREPO_BRANCH=$(git -C "$PERSONAL_MONOREPO_LOCATION" branch --show-current)
    echo "$MONOREPO_BRANCH"
    exit
  else
    export MONOREPO_BRANCH=master
  fi
fi

if [[ ! -v CLUSTER_NAME ]]; then
  if [[ ! -v ATILS_CURRENT_CONTEXT ]]; then
    read -p "Please enter the name of the cluster you want to use: " CLUSTER_NAME
  else
    export CLUSTER_NAME="$ATILS_CURRENT_CONTEXT"
  fi
fi

cat <<EOF | envsubst | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: master-stack
  namespace: argocd
spec:
  project: default
  sources:
    - repoURL: https://github.com/AidanHilt/PersonalMonorepo
      path: kubernetes/helm-charts/k8s-resources/master-stack
      targetRevision: $MONOREPO_BRANCH
      helm:
        valueFiles:
          - "\$values/kubernetes/argocd/configuration-data/$CLUSTER_NAME/master-stack.yaml"
    - repoURL: https://github.com/AidanHilt/PersonalMonorepo
      targetRevision: $MONOREPO_BRANCH
      ref: values
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
'';
in

{
  environment.systemPackages = [
    argocd-create-master-stack
  ];
}