#!/bin/bash

set -euo pipefail

# @lib: printing-and-output

read -rp "Enter app name: " APP_NAME
read -rp "Enter app namespace: " NAMESPACE

read -rp "Create a new helm chart? (y/n): " HELM_CHART
APP_TYPE=2
if [[ "$HELM_CHART" =~ ^[Yy]$ ]]; then
  helm-new-application --chart-name "$APP_NAME"
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
  read -rp "Prefix: " prefix
  if [[ -z "$prefix" ]]; then
    break
  fi
  if [[ ! "$prefix" =~ ^/ ]]; then
    prefix="/$prefix"
  fi
  PREFIXES+=("$prefix")
done

if [[ ${#PREFIXES[@]} -eq 0 ]]; then
  read -rp "Enter subdomain: " SUBDOMAIN
fi

if [[ ${#PREFIXES[@]} -eq 0 ]] && [[ -z "$SUBDOMAIN" ]]; then
  print_status "No prefixes or subdomains provided, skipping ingress and homepage"
else
  print_debug "Adding ingress for $APP_NAME"
  INGRESS_ARGS=""
  if [[ ${#PREFIXES[@]} -gt 0 ]]; then
    for prefix in "${PREFIXES[@]}"; do
      INGRESS_ARGS+="--prefix $prefix "
    done
  else
    INGRESS_ARGS="--subdomain $SUBDOMAIN"
  fi
  app-creator-add-ingress --app-name "$APP_NAME" --namespace "$NAMESPACE" "$INGRESS_ARGS"

  print_debug "Adding homepage link for $APP_NAME"
  HOMEPAGE_ARGS=""
  if [[ ${#PREFIXES[@]} -gt 0 ]]; then
    HOMEPAGE_ARGS="--prefix ${PREFIXES[0]}"
  else
    HOMEPAGE_ARGS="--subdomain $SUBDOMAIN"
  fi
  app-creator-add-homepage-link --app-name "$APP_NAME" "$HOMEPAGE_ARGS"
fi

SECRET_NAMES=()
SECRET_NAMESPACES=()
SERVICE_ACCOUNT_NAMES=()
POSTGRES_SECRETS=()

read -rp "Would you like to add any secrets? (y/n): " add_secrets

if [[ "$add_secrets" =~ ^[Yy]$ ]]; then
  while true; do
    read -rp "Enter secret name (or leave blank to finish) [default: $APP_NAME]: " secret_name

    if [[ -z "$secret_name" ]]; then
      if [[ ${#SECRET_NAMES[@]} -eq 0 ]]; then
        secret_name="$APP_NAME"
      else
        break
      fi
    fi

    read -rp "Enter namespace [default: $NAMESPACE]: " secret_namespace
    secret_namespace="${secret_namespace:-$NAMESPACE}"

    read -rp "Enter service account name [default: $APP_NAME]: " service_account_name
    service_account_name="${service_account_name:-$APP_NAME}"

    read -rp "Is this a postgres secret? (y/n): " is_postgres
    if [[ "$is_postgres" =~ ^[Yy]$ ]]; then
      postgres_secret="true"
    else
      postgres_secret="false"
    fi

    SECRET_NAMES+=("$secret_name")
    SECRET_NAMESPACES+=("$secret_namespace")
    SERVICE_ACCOUNT_NAMES+=("$service_account_name")
    POSTGRES_SECRETS+=("$postgres_secret")
  done

  for i in "${!SECRET_NAMES[@]}"; do
    echo "============================================"
    echo " You are adding kubernetes secrets"
    echo "============================================"
    app-creator-add-secret --secret-name "${SECRET_NAMES[$i]}" --destination-namespace "${SECRET_NAMESPACES[$i]}" --service-account-name "${SERVICE_ACCOUNT_NAMES[$i]}" --postgres-secret "${POSTGRES_SECRETS[$i]}"

    echo "================================================="
    echo " You are adding secret configuration to terraform"
    echo "================================================="
    app-creator-add-terraform-secret --secret-name "${SECRET_NAMES[$i]}" --secret-namespace "${SECRET_NAMESPACES[$i]}" --secret-mount "${SECRET_NAMESPACES[$i]}" --postgres-secret "${POSTGRES_SECRETS[$i]}"
  done
fi

read -rp "Do you need any postgres DBs? (y/n): " need_postgres

if [[ "$need_postgres" =~ ^[Yy]$ ]]; then
  print_debug "Adding postgres configuration"
  app-creator-add-postgres-config
fi

print_status "Successfully created app $APP_NAME"
