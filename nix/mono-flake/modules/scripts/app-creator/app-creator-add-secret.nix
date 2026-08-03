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
  echo "--secret-mount MOUNT The Vault mount to store this secret in"
  echo "--postgres-secret: [true|false] Whether or not this secret is a postgres user"
  echo ""
}

get_input() {
  local prompt="$1"
  local default="$2"
  local value
  if [ -n "$default" ]; then
    read -r -p "$prompt [$default]: " value
    value="''${value:-$default}"
  else
    read -r -p "$prompt: " value
  fi
  printf '%s' "$value"
}

add_secret_key() {
  local key_name is_pg_password set_value key_value
  key_name="$(get_input "Enter key name" "")"
  if [[ "$key_name" == "postgresPassword" ]]; then
    is_pg_password="y"
  else
    is_pg_password="$(get_input "Is this a postgres password? (y/n)" "n")"
  fi
  case $is_pg_password in
    [Yy]*)
      is_pg_password=true
      ;;
    *)
      is_pg_password=false
      ;;
  esac
  set_value=n
  if [[ "$is_pg_password" == "false" ]]; then
    set_value="$(get_input "Set a value for this key? (y/n)" "n")"
  fi
  if [ "$set_value" = "y" ]; then
    key_value="$(get_input "Enter value for $key_name" "")"
  else
    key_value=""
  fi
  SECRET_KEYS+=("$key_name|$is_pg_password|$key_value")
}

SECRET_NAME=""
DESTINATION_NAMESPACE=""
RESOURCE_NAME=""
SERVICE_ACCOUNT_NAME=""
SERVICE_ACCOUNT_CREATE=""
SERVICE_ACCOUNT_NAMESPACE=""
POSTGRES_SECRET=""
SECRET_MOUNT=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --secret-name)
      SECRET_NAME="$2"
      shift 2
      ;;
    --destination-namespace)
      DESTINATION_NAMESPACE="$2"
      shift 2
      ;;
    --resource-name)
      RESOURCE_NAME="$2"
      shift 2
      ;;
    --service-account-name)
      SERVICE_ACCOUNT_NAME="$2"
      shift 2
      ;;
    --service-account-create)
      SERVICE_ACCOUNT_CREATE="true"
      shift 1
      ;;
    --service-account-namespace)
      SERVICE_ACCOUNT_NAMESPACE="$2"
      shift 2
      ;;
    --postgres-secret)
      POSTGRES_SECRET="$2"
      shift 2
      ;;
    --secret-mount)
      SECRET_MOUNT="$2"
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

if [[ -z "$SECRET_NAME" ]]; then
  read -p "Enter the name of the secret: " SECRET_NAME
fi

if [[ -z "$DESTINATION_NAMESPACE" ]]; then
  read -p "Enter the destination namespace: " DESTINATION_NAMESPACE
fi

if [[ -z "$SECRET_MOUNT" ]]; then
  SECRET_MOUNT="$DESTINATION_NAMESPACE"
fi

CONFIGURE_SA="n"

if [[ -z "$SERVICE_ACCOUNT_NAME" ]]; then
  CONFIGURE_SA=$(get_input "Would you like to configure the service account? (y/n)" "n")
fi

if [[ "$CONFIGURE_SA" == "y" ]]; then
  SA_DEFAULT="$SECRET_NAME"
  if [[ -n "$RESOURCE_NAME" ]]; then
    SA_DEFAULT="$RESOURCE_NAME"
  fi

  if [[ -z "$SERVICE_ACCOUNT_NAME" ]]; then
    read -p "Enter the service account name [''${SA_DEFAULT}]: " SERVICE_ACCOUNT_NAME
    SERVICE_ACCOUNT_NAME="''${SERVICE_ACCOUNT_NAME:-$SA_DEFAULT}"
  fi

  if [[ -z "$SERVICE_ACCOUNT_CREATE" ]]; then
    SA_CREATE_INPUT=$(get_input "Should the service account be created? (y/n): " "n")
    if [[ "$SA_CREATE_INPUT" == "y" ]]; then
      SERVICE_ACCOUNT_CREATE="true"
    fi
  fi

  if [[ -z "$SERVICE_ACCOUNT_NAMESPACE" ]]; then
    read -p "Enter the service account namespace [''${DESTINATION_NAMESPACE}]: " SERVICE_ACCOUNT_NAMESPACE
  fi
fi

CONFIGURE_DEST=$(get_input "Would you like to configure the destination secret? (y/n): " "n")

if [[ "$CONFIGURE_DEST" == "y" ]]; then
  DESTINATION_FILE=$(mktemp)
  echo "destination:" > "$DESTINATION_FILE"

  $EDITOR "$DESTINATION_FILE"
fi

YQ_STRING=".\"$SECRET_NAME\".enabled=false | .\"$SECRET_NAME\".secretDestinationNamespace = \"$DESTINATION_NAMESPACE\""

if [[ -n "$RESOURCE_NAME" ]]; then
  YQ_STRING="$YQ_STRING | .\"$SECRET_NAME\".destination.name = \"$RESOURCE_NAME\""
fi

if [[ "$CONFIGURE_SA" == "y" ]]; then
  YQ_STRING="$YQ_STRING | .\"$SECRET_NAME\".serviceAccount.create = true"

  if [[ -n "$SERVICE_ACCOUNT_NAME" ]]; then
    YQ_STRING="$YQ_STRING | .\"$SECRET_NAME\".serviceAccount.name = \"$SERVICE_ACCOUNT_NAME\""
  fi

  if [[ -n "$SERVICE_ACCOUNT_NAMESPACE" ]]; then
    YQ_STRING="$YQ_STRING | .\"$SECRET_NAME\".serviceAccount.namespace = \"$SERVICE_ACCOUNT_NAMESPACE\""
  fi
fi

if [[ -v DESTINATION_FILE ]]; then
  YQ_STRING="$YQ_STRING | .\"$SECRET_NAME\" += load(\"$DESTINATION_FILE\")"
fi

SECRET_VALUES_FILE="$PERSONAL_MONOREPO_LOCATION/kubernetes/helm-charts/k8s-resources/vault-config/values.yaml"

print_debug "Executing yq modification with string: $YQ_STRING"
_modify-secret-values "$YQ_STRING" "$SECRET_VALUES_FILE"

if [[ -v DESTINATION_FILE ]]; then
  rm "$DESTINATION_FILE"
fi

print_debug "Collecting secret keys"
SECRET_KEYS=()
add_keys="$(get_input "Would you like to enter any secret keys? (y/n)" "n")"
while [ "$add_keys" = "y" ]; do
  add_secret_key
  add_keys="$(get_input "Add another key? (y/n)" "n")"
done

for entry in "''${SECRET_KEYS[@]}"; do
  key_name="$(cut -d'|' -f1 <<< "$entry")"
  is_pg_password="$(cut -d'|' -f2 <<< "$entry")"
  key_value="$(cut -d'|' -f3 <<< "$entry")"
  YQ_PATH=".''${SECRET_NAME}.data.''${key_name}"
  _modify-secret-values "$YQ_PATH={}" "$SECRET_VALUES_FILE"
  if [[ "$is_pg_password" == "true" ]]; then
    _modify-secret-values "$YQ_PATH.is_postgres_password=$is_pg_password" "$SECRET_VALUES_FILE"
  fi
  if [ -n "$key_value" ]; then
    _modify-secret-values "$YQ_PATH=\"$key_value\"" "$SECRET_VALUES_FILE"
  fi
done

print_status "Secret definition for $SECRET_NAME added to helm. Don't forget to run 'nix flake update' before running terraform to preserve changes."
'';
in

{
  environment.systemPackages = [
    app-creator-add-secret
  ];
}