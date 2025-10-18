{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

helm-k8s-resource-new-stack = pkgs.writeShellScriptBin "helm-k8s-resource-new-stack" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

OUTPUT_DIR="$PERSONAL_MONOREPO_LOCATION/kubernetes/helm-charts/k8s-resources"
CHART_NAME=""
STACK_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --chart-name)
      CHART_NAME="$2"
      shift 2
      ;;
    --stack-name)
      STACK_NAME="$2"
      shift 2
      ;;
    *)
      print_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "''${CHART_NAME}" ]]; then
  CHART_NAME="$(select-directory)"
fi

SELECTED_DIR="''${OUTPUT_DIR}/''${CHART_NAME}"

if [[ -z "''${STACK_NAME}" ]]; then
  read -r -p "Enter stack name: " STACK_NAME
fi

print_status "Editing values.yaml for stack ''${STACK_NAME}"
_edit-yaml-in-place "''${SELECTED_DIR}/values.yaml" "''${STACK_NAME}="

TEMPLATE_SOURCE="''${PERSONAL_MONOREPO_LOCATION}/helm/templates/stack-template.yaml"
TEMPLATE_DEST="''${SELECTED_DIR}/templates/''${STACK_NAME}.yaml"

print_status "Copying template to ''${TEMPLATE_DEST}"
cp "''${TEMPLATE_SOURCE}" "''${TEMPLATE_DEST}"

export STACK_NAME
envsubst < "''${TEMPLATE_DEST}" > "''${TEMPLATE_DEST}.tmp"
mv "''${TEMPLATE_DEST}.tmp" "''${TEMPLATE_DEST}"

'';
in

{
  environment.systemPackages = [
    helm-k8s-resource-new-stack
  ];
}