{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

app-creator-create-app = pkgs.writeShellScriptBin "app-creator-create-app" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

read -p "Enter app name: " APP_NAME
read -p "Enter app namespace ($APP_NAME): " NAMESPACE

if [[ -z $NAMESPACE ]]; then
  NAMESPACE="$APP_NAME"
fi

read -p "Create a new helm chart? (y/n): " HELM_CHART
APP_TYPE=2
if [[ "$HELM_CHART" =~ ^[Yy]$ ]]; then
  helm-new-application --chart-name $APP_NAME
  APP_TYPE=1
fi

echo "======================================"
echo " You are now creating the ArgoCD app"
echo "======================================"
if [[ "$APP_TYPE" == 2 ]]; then
  app-creator-add-argocd-app --app-name "$APP_NAME" --namespace "$NAMESPACE" --skip-default-values --skip-secure-values --app-type "$APP_TYPE"
else
  app-creator-add-argocd-app --app-name "$APP_NAME" --namespace "$NAMESPACE" --skip-default-values --skip-secure-values --app-type "$APP_TYPE" --repo "https://github.com/AidanHilt/PersonalMonorepo" --git-path "kubernetes/helm-charts/applications/$APP_NAME"
fi

echo "=========================================="
echo " You are now defining ingress for the app"
echo " Use prefixes for path-based routing, or"
echo " subdomains if desired. If nothing is input"
echo " the script will assume no access from"
echo " outside the cluster is desired and will"
echo " skip that and creating a homepage link"
echo "=========================================="

PREFIXES=()
SUBDOMAIN=""

print_status "Enter prefixes (one per line, press Enter on empty line to finish): "
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
  read -p "Enter subdomain: " SUBDOMAIN
fi

if [[ ''${#PREFIXES[@]} -eq 0 ]] && [[ -z "$SUBDOMAIN" ]]; then
  print_status "No prefixes or subdomains provided, skipping ingress and homepage"
else
  print_debug "Adding ingress for $APP_NAME"
  INGRESS_ARGS=""
  if [[ ''${#PREFIXES[@]} -gt 0 ]]; then
    for prefix in "''${PREFIXES[@]}"; do
      INGRESS_ARGS+="--prefix $prefix "
    done
  else
    INGRESS_ARGS="--subdomain $SUBDOMAIN"
  fi
  app-creator-add-ingress --app-name "$APP_NAME" --namespace "$NAMESPACE" $INGRESS_ARGS

  print_debug "Adding homepage link for $APP_NAME"
  HOMEPAGE_ARGS=""
  if [[ ''${#PREFIXES[@]} -gt 0 ]]; then
    HOMEPAGE_ARGS="--prefix ''${PREFIXES[0]}"
  else
    HOMEPAGE_ARGS="--subdomain $SUBDOMAIN"
  fi
  app-creator-add-homepage-link --app-name "$APP_NAME" $HOMEPAGE_ARGS
fi

read -p "Would you like to add any secrets? (y/n): " add_secrets

if [[ "$add_secrets" =~ ^[Yy]$ ]]; then
  app-creator-add-secret --secret-name "$APP_NAME" --destination-namespace "$NAMESPACE"

  CONTINUE="true"
  while "$CONTINUE"; do
    read -p "Enter another secret? [y/N]" add_another_secret
    if ! [[ "$add_another_secret" =~ ^[Yy]$ ]]; then
      CONTINUE="false"
    else
      app-creator-add-secret
    fi
  done
fi

read -p "Do you need any postgres DBs? (y/n): " need_postgres

if [[ "$need_postgres" =~ ^[Yy]$ ]]; then
  print_debug "Adding postgres configuration"
  app-creator-add-postgres-config
fi

print_status "Successfully created app $APP_NAME"
'';
in

{
  environment.systemPackages = [
    app-creator-create-app
  ];
}