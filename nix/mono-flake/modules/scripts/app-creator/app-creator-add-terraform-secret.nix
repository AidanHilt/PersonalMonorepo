{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

app-creator-add-terraform-secret = pkgs.writeShellScriptBin "app-creator-add-terraform-secret" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

show_help () {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  # Description goes here
  echo ""
  echo ""
  echo "OPTIONS:"
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
  is_pg_password="$(get_input "Is this a postgres password? (y/n)" "n")"
  case $is_pg_password in
    [Yy]*)
      is_pg_password=true
      ;;
    *)
      is_pg_password=false
      ;;
  esac
  set_value="$(get_input "Set a value for this key? (y/n)" "n")"
  if [ "$set_value" = "y" ]; then
    key_value="$(get_input "Enter value for $key_name" "")"
  else
    key_value=""
  fi
  SECRET_KEYS+=("$key_name|$is_pg_password|$key_value")
}


SECRET_NAME=""
SECRET_NAMESPACE=""
SECRET_MOUNT=""
POSTGRES_SECRET=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --secret-name)
      SECRET_NAME="$2"
      shift 2
      ;;
      --secret-namespace)
      SECRET_NAMESPACE="$2"
      shift 2
      ;;
      --secret-mount)
      SECRET_MOUNT="$2"
      shift 2
      ;;
      --postgres-secret)
      POSTGRES_SECRET="true"
      shift 2
      ;;
      --help|-h)
      show_help
      exit 0
      ;;
      *)
      print_error "Unknown option: $2"
      exit 1
      ;;
  esac
done


if [ -z "$SECRET_NAME" ]; then
  SECRET_NAME="$(get_input "Enter secret name" "")"
fi

if [ -z "$SECRET_NAMESPACE" ]; then
  SECRET_NAMESPACE="$(get_input "Enter secret namespace" "")"
fi

if [ -z "$SECRET_MOUNT" ]; then
  SECRET_MOUNT="$(get_input "Enter secret mount" "")"
fi

if [ -z "$POSTGRES_SECRET" ]; then
  ANSWER="$(get_input "Does the secret contain postgres creds? (y/n)" "n")"
  case $ANSWER in
    [Yy]*)
      POSTGRES_SECRET=true
      ;;
    *)
      POSTGRES_SECRET=false
      ;;
  esac
fi

print_debug "Collecting secret keys"
SECRET_KEYS=()
add_keys="$(get_input "Would you like to enter any secret keys? (y/n)" "n")"
while [ "$add_keys" = "y" ]; do
  add_secret_key
  add_keys="$(get_input "Add another key? (y/n)" "n")"
done

LOCAL_FILE="''${PERSONAL_MONOREPO_LOCATION}/terraform/vault-config/locals.tf.json"
print_debug "Updating locals.tf.json at $LOCAL_FILE"

for entry in "''${SECRET_KEYS[@]}"; do
  key_name="$(cut -d'|' -f1 <<< "$entry")"
  is_pg_password="$(cut -d'|' -f2 <<< "$entry")"
  key_value="$(cut -d'|' -f3 <<< "$entry")"
  HCLEDIT_PATH=".locals[0].secret_definitions.''${SECRET_NAME}.data.''${key_name}"
  jq "$HCLEDIT_PATH.is_postgres_password=$is_pg_password" "$LOCAL_FILE" > tmp.json && mv tmp.json "$LOCAL_FILE"
  if [ -n "$key_value" ]; then
    jq "$HCLEDIT_PATH.value=\"$key_value\"" "$LOCAL_FILE" > tmp.json && mv tmp.json "$LOCAL_FILE"
  fi
done

jq \
  --arg name "$SECRET_NAME" \
  --arg ns "$SECRET_NAMESPACE" \
  --arg mount "$SECRET_MOUNT" \
  --arg pg "$POSTGRES_SECRET" \
  '
  .locals[0].secret_definitions[$name].namespace = $ns
  | .locals[0].secret_definitions[$name].mount = $mount
  | .locals[0].secret_definitions[$name].postgres_secret = $pg
  ' "$LOCAL_FILE" > tmp.json && mv tmp.json "$LOCAL_FILE"


  print_status "Secret definition for $SECRET_NAME added to locals file"
'';
in

{
  environment.systemPackages = [
    app-creator-add-terraform-secret
  ];
}