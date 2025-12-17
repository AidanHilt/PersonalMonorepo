{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };
modify-ingress-values = import ../lib/_modify-ingress-values.nix { inherit pkgs; };

app-creator-add-homepage-link = pkgs.writeShellScriptBin "app-creator-add-homepage-link" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}
source ${modify-ingress-values.modify-ingress-values}

HOMEPAGE_VALUES_FILE=$PERSONAL_MONOREPO_LOCATION/kubernetes/helm-charts/k8s-resources/homepage-config/values.yaml

APP_NAME=""
PREFIX=""
DESCRIPTION=""
GROUP=""
ICON=""
SUBDOMAIN=""
DISPLAY_NAME=""

show_help () {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  # Description goes here
  echo "Create ingress resources for istio"
  echo ""
  echo "OPTIONS:"
  echo "  --app-name, -a: The name of the app to create ingress for"
  echo "  --prefix, -r: A prefix used for path-based routing. Can be provided multiple times"
  echo "  --subdomain, -s: The subdomain this app is to be served on"
  echo "  --description, -d: A short blurb about the app to display on the homepage"
  echo "  --group, -g: The group this app belongs under on the homepage"
  echo "  --icon, -i: The icon to use. Can be a URL, or following this guide: https://gethomepage.dev/configs/services/#icons"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --app-name|-a)
    APP_NAME="$2"
    shift 2
    ;;
    --description|-d)
    DESRIPTION="$2"
    shift 2
    ;;
    --group|-g)
    GROUP="$2"
    shift 2
    ;;
    --icon|-i)
    ICON="$2"
    shift 2
    ;;
    --prefix|-r)
    PREFIX="$2"
    shift 2
    ;;
    --subdomain|-s)
    SUBDOMAIN="$2"
    shift 2
    ;;
    --display-name|-n)
    DISPLAY_NAME="$2"
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
  while true; do
    read -p "Enter the name of the app: " APP_NAME
    if [[ -n "$APP_NAME" ]]; then
      break
    fi
    print_warning "App name cannot be empty"
  done
fi

if [[ -z $PREFIX && -z "$SUBDOMAIN" ]]; then
  read -p "Enter prefix or leave blank: " PREFIX
fi

if [[ -z $PREFIX && -z "$SUBDOMAIN" ]] ; then
  while true; do
    read -p "Enter subdomain: " SUBDOMAIN
    if [[ -n "$SUBDOMAIN" ]]; then
      break
    fi
    print_warning "Subdomain cannot be empty"
  done
fi

if [[ -z "$DESCRIPTION" ]]; then
  while true; do
    read -p "Enter a short description of the app: " DESCRIPTION
    if [[ -n "$DESCRIPTION" ]]; then
      break
    fi
    print_warning "Description cannot be empty"
  done
fi

if [[ -z "$DISPLAY_NAME" ]]; then
  DEFAULT_DISPLAY_NAME=$(echo "$APP_NAME" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
  read -p "Enter a display name with proper formatting (default: $DEFAULT_DISPLAY_NAME): " display_name
  DISPLAY_NAME=''${display_name:-$DEFAULT_DISPLAY_NAME}

fi

if [[ -z "$ICON" ]]; then
  read -p "Enter a path for the icon. See https://gethomepage.dev/configs/services/#icons (default sh-$APP_NAME): " svc_name
  SERVICE_NAME=''${svc_name:-sh-$APP_NAME}
fi

if [[ -z "$GROUP" ]]; then
  while true; do
    read -p "Enter the group name of the app: " GROUP
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

HOMEPAGE_YQ_STRING=".$APP_NAME.enabled=false ''${ROUTE_CONFIG_STRING}"
HOMEPAGE_YQ_STRING+=".$APP_NAME.description='$DESCRIPTION'"
HOMEPAGE_YQ_STRING+=".$APP_NAME.icon=$ICON"
HOMEPAGE_YQ_STRING+=".$APP_NAME.group=$GROUP"


_modify-ingress-values "$HOMEPAGE_YQ_STRING" "$HOMEPAGE_VALUES_FILE"
'';
in

{
  environment.systemPackages = [
    app-creator-add-homepage-link
  ];
}