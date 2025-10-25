{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };
modify-ingress-values = import ../lib/_modify-ingress-values.nix { inherit pkgs; };

app-creator-add-ingress = pkgs.writeShellScriptBin "app-creator-add-ingress" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}
source ${modify-ingress-values.modify-ingress-values}

ISTIO_VALUES_FILE=$PERSONAL_MONOREPO_LOCATION/kubernetes/helm-charts/k8s-resources/istio-ingress-config/values.yaml
NGINX_VALUES_FILE=$PERSONAL_MONOREPO_LOCATION/kubernetes/helm-charts/k8s-resources/nginx-ingress-config/values.yaml

APP_NAME=""
PREFIXES=()
NAMESPACE=""
SERVICE_NAME=""
DESTINATION_PORT=""
SUBDOMAIN=""

show_help () {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  # Description goes here
  echo ""
  echo ""
  echo "OPTIONS:"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --app-name|-a)
    APP_NAME="$2"
    shift 2
    ;;
    --namespace|-n)
    NAMESPACE="$2"
    shift 2
    ;;
    --service-name|-s)
    SERIVCE_NAME="$2"
    shift 2
    ;;
    --port|-p)
    DESTINATION_PORT="$2"
    shift 2
    ;;
    --prefix|-r)
    PREFIXES+=("$2")
    shift 2
    ;;
    --subdomain|-d)
    SUBDOMAIN="$2"
    shift 2
    ;;
    --help|-h)
    show_help
    exit 0
    ;;
    *)
    print_error "Unknown option: $1"
    exit 1
    ;;
  esac
done

if [[ -z "$APP_NAME" ]]; then
  read -p "Enter the name of the app: " APP_NAME
fi

if [[ ''${#PREFIXES[@]} -eq 0 ]]; then
  print_status "Enter prefixes (one per line, press Enter on empty line to finish):"
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
fi

if [[ ''${#PREFIXES[@]} -eq 0 && -z "$SUBDOMAIN" ]] ; then
  while true; do
    read -p "Enter subdomain: " SUBDOMAIN
    if [[ -n "$SUBDOMAIN" ]]; then
      break
    fi
    print_warning "Subdomain cannot be empty"
  done
fi

if [[ -z "$NAMESPACE" ]]; then
  while true; do
    read -p "Enter namespace: " NAMESPACE
    if [[ -n "$NAMESPACE" ]]; then
      break
    fi
    print_warning "Namespace cannot be empty"
  done
fi

if [[ -z "$SERVICE_NAME" ]]; then
  read -p "Enter destination service name (default $APP_NAME): " svc_name
  SERVICE_NAME=''${svc_name:-$APP_NAME}
fi

if [[ -z "$DESTINATION_PORT" ]]; then
  read -p "Enter destination port (default: 80): " port
  DESTINATION_PORT=''${port:-80}
fi

export PREFIXES_JSON=$(printf '%s\n' "''${PREFIXES[@]}" | jq -R . | jq -s .)

ISTIO_YQ_STRING=".$APP_NAME.enabled=false "

if [[ ''${#PREFIXES[@]} -ge 0 ]]; then
  ISTIO_YQ_STRING+="| .$APP_NAME.prefixes=env(PREFIXES_JSON) "
fi

if [[ ! -z "$SUBDOMAIN" ]]; then
  ISTIO_YQ_STRING+="| .$APP_NAME.subdomain=\"$SUBDOMAIN\""
fi

ISTIO_YQ_STRING+="| .$APP_NAME.destinationSvc=\"$SERVICE_NAME.$NAMESPACE.svc.cluster.local\""

_modify-ingress-values "$ISTIO_YQ_STRING" "$ISTIO_VALUES_FILE"


NGINX_YQ_STRING=".$APP_NAME.enabled=false | .$APP_NAME.namespace=\"$NAMESPACE\" | .$APP_NAME.prefixes=env(PREFIXES_JSON) | .$APP_NAME.destinationSvc=\"$SERVICE_NAME\""
_modify-ingress-values "$NGINX_YQ_STRING" "$NGINX_VALUES_FILE"
'';
in

{
  environment.systemPackages = [
    app-creator-add-ingress
  ];
}