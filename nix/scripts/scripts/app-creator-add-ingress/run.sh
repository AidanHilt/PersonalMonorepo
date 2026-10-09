#!/bin/bash

set -euo pipefail

# @lib: printing-and-output
# @lib: args-and-help
# @lib: modify-ingress-values

ISTIO_VALUES_FILE=$PERSONAL_MONOREPO_LOCATION/kubernetes/helm-charts/k8s-resources/istio-ingress-config/values.yaml

APP_NAME=""
PREFIXES=()
NAMESPACE=""
SERVICE_NAME=""
DESTINATION_PORT=""
SUBDOMAIN=""

args_description "Create ingress resources for istio"
args_value "-a" "--app-name" APP_NAME "APP_NAME" "The name of the app to create ingress for"
args_value "-n" "--namespace" NAMESPACE "NAMESPACE" "The namespace the app will live in. Needed to properly route requests"
args_value "-s" "--service-name" SERVICE_NAME "SERVICE_NAME" "The name of the kubernetes service associated with this app"
args_value "-p" "--port" DESTINATION_PORT "PORT" "The port number used by the service. Defaults to 80"
args_repeat "-r" "--prefix" PREFIXES "PREFIX" "A prefix used for path-based routing. Can be provided multiple times"
args_value "-d" "--subdomain" SUBDOMAIN "SUBDOMAIN" "The subdomain this app is to be served on"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

if [[ -z "$APP_NAME" ]]; then
  read -rp "Enter the name of the app: " APP_NAME
fi

if [[ ${#PREFIXES[@]} -eq 0 && -z "$SUBDOMAIN" ]]; then
  print_status "Enter prefixes (one per line, press Enter on empty line to finish):"
  while true; do
    read -rp "Prefix: " prefix
    if [[ -z "$prefix" ]]; then
      break
    fi
    if [[ ! "$prefix" =~ ^/ ]]; then
      prefix="/$prefix"
    fi
    PREFIXES+=("$prefix")
  done
fi

if [[ ${#PREFIXES[@]} -eq 0 && -z "$SUBDOMAIN" ]]; then
  while true; do
    read -rp "Enter subdomain: " SUBDOMAIN
    if [[ -n "$SUBDOMAIN" ]]; then
      break
    fi
    print_warning "Subdomain cannot be empty"
  done
fi

if [[ -z "$NAMESPACE" ]]; then
  while true; do
    read -rp "Enter namespace: " NAMESPACE
    if [[ -n "$NAMESPACE" ]]; then
      break
    fi
    print_warning "Namespace cannot be empty"
  done
fi

if [[ -z "$SERVICE_NAME" ]]; then
  echo "$SERVICE_NAME"
  read -rp "Enter destination service name (default $APP_NAME): " svc_name
  SERVICE_NAME=${svc_name:-$APP_NAME}
fi

if [[ -z "$DESTINATION_PORT" ]]; then
  read -rp "Enter destination port (default: 80): " port
  DESTINATION_PORT=${port:-80}
fi

PREFIXES_JSON=$(printf '%s\n' "${PREFIXES[@]}" | jq -R . | jq -s .)

export PREFIXES_JSON

ROUTE_CONFIG_STRING=""

if [[ ${#PREFIXES[@]} -gt 0 ]]; then
  ROUTE_CONFIG_STRING+="| .$APP_NAME.prefixes=env(PREFIXES_JSON) "
fi

if [[ ! -z "$SUBDOMAIN" ]]; then
  ROUTE_CONFIG_STRING+="| .$APP_NAME.subdomain=\"$SUBDOMAIN\""
fi

ISTIO_YQ_STRING=".$APP_NAME.enabled=false ${ROUTE_CONFIG_STRING}"
ISTIO_YQ_STRING+="| .$APP_NAME.destinationSvc=\"$SERVICE_NAME.$NAMESPACE.svc.cluster.local\""

if [[ "$DESTINATION_PORT" != 80 ]]; then
  ISTIO_YQ_STRING+="| .$APP_NAME.destinationPort=\"$DESTINATION_PORT\""
fi

modify-ingress-values "$ISTIO_YQ_STRING" "$ISTIO_VALUES_FILE"
