{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };
modify-secret-values = (import ../lib/_modify-secret-values.nix { inherit pkgs; }).script;

app-creator-add-secret = pkgs.writeShellScriptBin "app-creator-add-secret" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}
source ${modify-secret-values}

show_help () {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Add a new secret to the vault-config chart"
  echo ""
  echo "OPTIONS:"
  echo "--secret-name: The name of the secret"
  echo "--destination-namespace: The destination namespace for the secret"
  echo "--resource-name: Override for the resource name"
  echo "--service-account-create: Takes no arguments. If provided, set service account create to true"
  echo "--service-account-name: The name of the service account"
  echo ""
}

secret_name=""
destination_namespace=""
resource_name=""
service_account_name=""
service_account_create=""
service_account_namespace=""
destination_config=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --secret-name)
      secret_name="$2"
      shift 2
      ;;
    --destination-namespace)
      destination_namespace="$2"
      shift 2
      ;;
    --resource-name)
      resource_name="$2"
      shift 2
      ;;
    --service-account-name)
      service_account_name="$2"
      shift 2
      ;;
    --service-account-create)
      service_account_create="true"
      shift 1
      ;;
    --service-account-namespace)
      service_account_namespace="$2"
      shift 2
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      print_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$secret_name" ]]; then
  read -p "Enter the name of the secret: " secret_name
fi

if [[ -z "$destination_namespace" ]]; then
  read -p "Enter the destination namespace: " destination_namespace
fi

if [[ -z "$resource_name" ]]; then
  read -p "Enter the resource name (optional): " resource_name
fi

read -p "Would you like to configure the service account? (y/N): " configure_sa

if [[ "$configure_sa" == "y" ]]; then
  SA_DEFAULT="$secret_name"
  if [[ -n "$resource_name" ]]; then
    SA_DEFAULT="$resource_name"
  fi

  if [[ -z "$service_account_name" ]]; then
    read -p "Enter the service account name [''${SA_DEFAULT}]: " service_account_name
    service_account_name="''${service_account_name:-$SA_DEFAULT}"
  fi

  if [[ -z "$service_account_create" ]]; then
    read -p "Should the service account be created? (y/N): " sa_create_input
    if [[ "$sa_create_input" == "y" ]]; then
      service_account_create="true"
    fi
  fi

  if [[ -z "$service_account_namespace" ]]; then
    read -p "Enter the service account namespace [''${destination_namespace}]: " service_account_namespace
  fi
fi

read -p "Would you like to configure the destination secret? (y/N): " configure_dest

if [[ "$configure_dest" == "y" ]]; then
  TEMP_FILE=$(mktemp)
  echo "destination:" > "$TEMP_FILE"

  $EDITOR "$TEMP_FILE"

  destination_config=$(yq eval '.destination' "$TEMP_FILE")
  rm "$TEMP_FILE"
fi

YQ_STRING="\"$secret_name\".enabled=false \"$secret_name\".destination.namespace = \"$destination_namespace\""

if [[ -n "$resource_name" ]]; then
  YQ_STRING="$YQ_STRING | .secrets.\"$secret_name\".destination.name = \"$resource_name\""
fi

if [[ "$configure_sa" == "y" ]]; then
  YQ_STRING="$YQ_STRING | .secrets.\"$secret_name\".serviceAccount.create = true"

  if [[ -n "$service_account_name" ]]; then
    YQ_STRING="$YQ_STRING | .secrets.\"$secret_name\".serviceAccount.name = \"$service_account_name\""
  fi

  if [[ -n "$service_account_namespace" ]]; then
    YQ_STRING="$YQ_STRING | .secrets.\"$secret_name\".serviceAccount.namespace = \"$service_account_namespace\""
  fi
fi

if [[ -n "$destination_config" && "$destination_config" != "null" ]]; then
  ESCAPED_DEST=$(echo "$destination_config" | yq eval -o=json)
  YQ_STRING="$YQ_STRING | .secrets.\"$secret_name\".destination += $ESCAPED_DEST"
fi

SECRET_VALUES_FILE="$PERSONAL_MONOREPO_LOCATION/kubernetes/helm-charts/k8s-resources/vault-config/values.yaml"

print_debug "Executing yq modification with string: $YQ_STRING"
_modify-secret-values "$YQ_STRING" "$SECRET_VALUES_FILE"

print_status "Secret configuration completed successfully"
'';
in

{
  environment.systemPackages = [
    app-creator-add-secret
  ];
}