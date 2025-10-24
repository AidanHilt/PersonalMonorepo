{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };
modify-ingress-values = import ../lib/_modify-ingress-values.nix { inherit pkgs; };

app-creator-add-ingress = pkgs.writeShellScriptBin "app-creator-add-ingress" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}
source ${modify-ingress-values.modify-ingress-values}

ISTIO_VALUES_FILE=$PERSONAL_MONOREPO_LOCATION/kubernetes/k8s-resources/istio-ingress-config/values.yaml
NGINX_VALUES_FILE=$PERSONAL_MONOREPO_LOCATION/kubernetes/k8s-resources/nginx-ingress-config/values.yaml

read -p "Enter the name of the app: " APP_NAME

print_status "Enter prefixes (one per line, press Enter on empty line to finish):"
PREFIXES=()
while true; do
  read -p "Prefix: " prefix
  if [[ -z "$prefix" ]]; then
    break
  fi
  if [[ ! "$prefix" =~ ^/ ]]; then
    prefix="/$prefix"
  fi
  PREFIXES+=("$prefix")
done

if [[ ''${#PREFIXES[@]} -eq 0 ]]; then
  while true; do
    read -p "Enter subdomain: " SUBDOMAIN
    if [[ -n "$SUBDOMAIN" ]]; then
      break
    fi
    print_warning "Subdomain cannot be empty"
  done
fi

while true; do
  read -p "Enter namespace: " NAMESPACE
  if [[ -n "$NAMESPACE" ]]; then
    break
  fi
  print_warning "Namespace cannot be empty"
done

read -p "Enter destination service name (default $APP_NAME): " svc_name
SERVICE_NAME=''${svc_name:-$APP_NAME}

read -p "Enter destination port (default: 80): " port
DESTINATION_PORT=''${port:-80}

export PREFIXES_JSON=$(printf '%s\n' "''${PREFIXES[@]}" | jq -R . | jq -s .)

ISTIO_YQ_STRING=".$APP_NAME.enabled=false | .$APP_NAME.prefixes=env(PREFIXES_JSON) | .$APP_NAME.destinationSvc=\"$SERVICE_NAME.$NAMESPACE.svc.cluster.local\""
_modify-ingress-values "$ISTIO_YQ_STRING" "$ISTIO_VALUES_FILE"
'';
in

{
  environment.systemPackages = [
    app-creator-add-ingress
  ];
}