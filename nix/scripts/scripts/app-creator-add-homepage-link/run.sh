#!/bin/bash

set -euo pipefail

# @lib: printing-and-output
# @lib: args-and-help
# @lib: modify-ingress-values

HOMEPAGE_VALUES_FILE=$PERSONAL_MONOREPO_LOCATION/kubernetes/helm-charts/k8s-resources/homepage-config/values.yaml

APP_NAME=""
PREFIX=""
DESCRIPTION=""
GROUP=""
ICON=""
SUBDOMAIN=""
DISPLAY_NAME=""

args_description "Create ingress resources for istio"
args_value "-a" "--app-name" APP_NAME "APP_NAME" "The name of the app to create ingress for"
args_value "-r" "--prefix" PREFIX "PREFIX" "A prefix used for path-based routing. Can be provided multiple times"
args_value "-s" "--subdomain" SUBDOMAIN "SUBDOMAIN" "The subdomain this app is to be served on"
args_value "-d" "--description" DESCRIPTION "DESCRIPTION" "A short blurb about the app to display on the homepage"
args_value "-g" "--group" GROUP "GROUP" "The group this app belongs under on the homepage"
args_value "-i" "--icon" ICON "ICON" "The icon to use. Can be a URL, or following this guide: https://gethomepage.dev/configs/services/#icons"
args_value "-n" "--display-name" DISPLAY_NAME "DISPLAY_NAME" "Override the display name shown on the homepage"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

if [[ -z "$APP_NAME" ]]; then
  while true; do
    read -rp "Enter the name of the app: " APP_NAME
    if [[ -n "$APP_NAME" ]]; then
      break
    fi
    print_warning "App name cannot be empty"
  done
fi

if [[ -z $PREFIX && -z "$SUBDOMAIN" ]]; then
  read -rp "Enter prefix or leave blank: " PREFIX
fi

if [[ -z $PREFIX && -z "$SUBDOMAIN" ]]; then
  while true; do
    read -rp "Enter subdomain: " SUBDOMAIN
    if [[ -n "$SUBDOMAIN" ]]; then
      break
    fi
    print_warning "Subdomain cannot be empty"
  done
fi

if [[ -z "$DESCRIPTION" ]]; then
  while true; do
    read -rp "Enter a short description of the app: " DESCRIPTION
    if [[ -n "$DESCRIPTION" ]]; then
      break
    fi
    print_warning "Description cannot be empty"
  done
fi

if [[ -z "$DISPLAY_NAME" ]]; then
  DEFAULT_DISPLAY_NAME=$(echo "$APP_NAME" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
  read -rp "Enter a display name with proper formatting (default: $DEFAULT_DISPLAY_NAME): " display_name
  DISPLAY_NAME=${display_name:-$DEFAULT_DISPLAY_NAME}

fi

if [[ -z "$ICON" ]]; then
  read -rp "Enter a path for the icon. See https://gethomepage.dev/configs/services/#icons (default sh-$APP_NAME): " svc_name
  ICON=${svc_name:-sh-$APP_NAME}
fi

if [[ -z "$GROUP" ]]; then
  while true; do
    read -rp "Enter the group name of the app: " GROUP
    if [[ -n "$GROUP" ]]; then
      break
    fi
    print_warning "Group cannot be empty"
  done
fi

ROUTE_CONFIG_STRING=""

if [[ ! -z "$PREFIX" ]]; then
  ROUTE_CONFIG_STRING+="| .$APP_NAME.prefixes=[\"$PREFIX\"] "
fi

if [[ ! -z "$SUBDOMAIN" ]]; then
  ROUTE_CONFIG_STRING+="| .$APP_NAME.subdomain=\"$SUBDOMAIN\""
fi

HOMEPAGE_YQ_STRING=".$APP_NAME.enabled=false ${ROUTE_CONFIG_STRING}"
HOMEPAGE_YQ_STRING+="| .$APP_NAME.description=\"$DESCRIPTION\""
HOMEPAGE_YQ_STRING+="| .$APP_NAME.icon=\"$ICON\""
HOMEPAGE_YQ_STRING+="| .$APP_NAME.group=\"$GROUP\""

modify-ingress-values "$HOMEPAGE_YQ_STRING" "$HOMEPAGE_VALUES_FILE"
