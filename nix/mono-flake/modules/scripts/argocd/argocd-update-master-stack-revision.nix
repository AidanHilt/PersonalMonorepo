{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

argocd-update-master-stack-revision = pkgs.writeShellScriptBin "argocd-update-master-stack-revision" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

GIT_BRANCH=""

show_help () {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Update master-stack in the current kubernetes cluster. Defaults to current personal monorepo branch"
  echo ""
  echo "OPTIONS:"
  echo "--master: Syncs back to the master branch"
  echo "--branch-name: Name a branch to sync to"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --master|-m)
    CURRENT_BRANCH="master"
    shift 1
    ;;
    --branch-name|-b)
    CURRENT_BRANCH="$2"
    shift 2
    ;;
    --help|-h)
    show_help
    exit 0
    ;;
  esac
done

cd "$PERSONAL_MONOREPO_LOCATION" || {
  print_error "Failed to change directory to $PERSONAL_MONOREPO_LOCATION"
  exit 1
}

if [ -z "$CURRENT_BRANCH" ]; then
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  print_debug "Current branch: $CURRENT_BRANCH"
fi

if ! kubectl get application master-stack -n argocd &>/dev/null; then
  print_debug "master-stack application does not exist in argocd namespace"
  exit 0
fi

print_debug "Found master-stack application, updating targetRevision to $CURRENT_BRANCH"

SOURCES_COUNT=$(kubectl get application master-stack -n argocd -o json | jq '.spec.sources | length')
print_debug "Found $SOURCES_COUNT sources to update"

for i in $(seq 0 $((SOURCES_COUNT - 1))); do
  kubectl patch application master-stack -n argocd --type=json \
    -p="[{\"op\": \"replace\", \"path\": \"/spec/sources/$i/targetRevision\", \"value\": \"$CURRENT_BRANCH\"}]"
  print_debug "Updated source $i targetRevision to $CURRENT_BRANCH"
done

print_status "Successfully updated all targetRevisions to $CURRENT_BRANCH"
'';
in

{
  environment.systemPackages = [
    argocd-update-master-stack-revision
  ];
}