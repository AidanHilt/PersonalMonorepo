{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

app-creator-create-app = pkgs.writeShellScriptBin "app-creator-create-app" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

read -p "Enter app name: " APP_NAME
read -p "Enter app namespace: " NAMESPACE

read -p "Create a new helm chart? (y/n): " HELM_CHART
if [[ "$HELM_CHART" =~ ^[Yy]$ ]]; then
  helm-new-application --chart-name $APP_NAME
fi

echo "========================================="
echo " You are now creating the ArgoCD app"
echo "========================================="
app-creator-add-argocd-app --app-name "$APP_NAME" --namespace "$NAMESPACE" --skip-default-values --skip-secure-values

print_debug "Adding ingress for $APP_NAME"
echo "========================================="
echp " You are now creating the ingress"
echo "========================================="
app-creator-add-ingress --app-name "$APP_NAME" --namespace "$NAMESPACE"

declare -a SECRET_NAMES
declare -a SECRET_NAMESPACES
declare -a SERVICE_ACCOUNT_NAMES
declare -a POSTGRES_SECRETS

read -p "Would you like to add any secrets? (y/n): " add_secrets

if [[ "$add_secrets" =~ ^[Yy]$ ]]; then
  while true; do
    read -p "Enter secret name (or leave blank to finish) [default: $APP_NAME]: " secret_name

    if [[ -z "$secret_name" ]]; then
      if [[ ''${#SECRET_NAMES[@]} -eq 0 ]]; then
        secret_name="$APP_NAME"
      else
        break
      fi
    fi

    read -p "Enter namespace [default: $NAMESPACE]: " secret_namespace
    secret_namespace="''${secret_namespace:-$NAMESPACE}"

    read -p "Enter service account name [default: $APP_NAME]: " service_account_name
    service_account_name="''${service_account_name:-$APP_NAME}"

    read -p "Is this a postgres secret? (y/n): " is_postgres
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

  for i in "''${!SECRET_NAMES[@]}"; do
    print_debug "Adding secret ''${SECRET_NAMES[$i]}"
    app-creator-add-secret --secret-name "''${SECRET_NAMES[$i]}" --destination-namespace "''${SECRET_NAMESPACES[$i]}" --service-account-name "''${SERVICE_ACCOUNT_NAMES[$i]}"

    print_debug "Adding terraform secret ''${SECRET_NAMES[$i]}"
    app-creator-add-terraform-secret --secret-name "''${SECRET_NAMES[$i]}" --secret-namespace "''${SECRET_NAMESPACES[$i]}" --postgres-secret "''${POSTGRES_SECRETS[$i]}"
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