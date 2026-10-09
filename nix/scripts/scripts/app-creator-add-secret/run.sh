#!/bin/bash

set -euo pipefail

# @lib: printing-and-output
# @lib: args-and-help
# @lib: _modify-secret-values

secret_name=""
destination_namespace=""
resource_name=""
service_account_name=""
service_account_create=""
service_account_namespace=""
#destination_config=""
#postgres_secret=""

# --postgres-secret was never wired up as a real option (kept here, still
# unused/commented, exactly as in the hand-rolled parser this replaced):
#   --postgres-secret)
#     postgres_secret="$2"
#     shift 2
#     ;;

args_description "Add a new secret to the vault-config chart"
args_value "" "--secret-name" secret_name "NAME" "The name of the secret"
args_value "" "--destination-namespace" destination_namespace "NAMESPACE" "The destination namespace for the secret"
args_value "" "--resource-name" resource_name "NAME" "Override for the resource name"
args_flag "" "--service-account-create" service_account_create "Takes no arguments. If provided, set service account create to true"
args_value "" "--service-account-name" service_account_name "NAME" "The name of the service account"
args_value "" "--service-account-namespace" service_account_namespace "NAMESPACE" "The namespace of the service account"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

if [[ -z "$secret_name" ]]; then
  read -rp "Enter the name of the secret: " secret_name
fi

if [[ -z "$destination_namespace" ]]; then
  read -rp "Enter the destination namespace: " destination_namespace
fi

configure_sa="n"

if [[ -z "$service_account_name" ]]; then
  read -rp "Would you like to configure the service account? (y/N): " configure_sa
fi

if [[ "$configure_sa" == "y" ]]; then
  SA_DEFAULT="$secret_name"
  if [[ -n "$resource_name" ]]; then
    SA_DEFAULT="$resource_name"
  fi

  if [[ -z "$service_account_name" ]]; then
    read -rp "Enter the service account name [${SA_DEFAULT}]: " service_account_name
    service_account_name="${service_account_name:-$SA_DEFAULT}"
  fi

  if [[ -z "$service_account_create" ]]; then
    read -rp "Should the service account be created? (y/N): " sa_create_input
    if [[ "$sa_create_input" == "y" ]]; then
      service_account_create="true"
    fi
  fi

  if [[ -z "$service_account_namespace" ]]; then
    read -rp "Enter the service account namespace [${destination_namespace}]: " service_account_namespace
  fi
fi

read -rp "Would you like to configure the destination secret? (y/N): " configure_dest

if [[ "$configure_dest" == "y" ]]; then
  DESTINATION_FILE=$(mktemp)
  echo "destination:" >"$DESTINATION_FILE"

  $EDITOR "$DESTINATION_FILE"
fi

YQ_STRING=".\"$secret_name\".enabled=false | .\"$secret_name\".secretDestinationNamespace = \"$destination_namespace\""

if [[ -n "$resource_name" ]]; then
  YQ_STRING="$YQ_STRING | .\"$secret_name\".destination.name = \"$resource_name\""
fi

if [[ "$configure_sa" == "y" ]]; then
  YQ_STRING="$YQ_STRING | .\"$secret_name\".serviceAccount.create = true"

  if [[ -n "$service_account_name" ]]; then
    YQ_STRING="$YQ_STRING | .\"$secret_name\".serviceAccount.name = \"$service_account_name\""
  fi

  if [[ -n "$service_account_namespace" ]]; then
    YQ_STRING="$YQ_STRING | .\"$secret_name\".serviceAccount.namespace = \"$service_account_namespace\""
  fi
fi

if [[ -v DESTINATION_FILE ]]; then
  YQ_STRING="$YQ_STRING | .\"$secret_name\" += load(\"$DESTINATION_FILE\")"
fi

SECRET_VALUES_FILE="$PERSONAL_MONOREPO_LOCATION/kubernetes/helm-charts/k8s-resources/vault-config/values.yaml"

print_debug "Executing yq modification with string: $YQ_STRING"
modify-secret-values "$YQ_STRING" "$SECRET_VALUES_FILE"

if [[ -v DESTINATION_FILE ]]; then
  rm "$DESTINATION_FILE"
fi

print_status "Secret configuration completed successfully"
