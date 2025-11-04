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

SECRET_NAME=""
SECRET_NAMESPACE=""
SECRET_MOUNT=""
POSTGRES_SECRET=false

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --secret-name=*) SECRET_NAME="‘''${arg#*=}" ;;
      --secret-namespace=*) SECRET_NAMESPACE="‘''${arg#*=}" ;;
      --secret-mount=*) SECRET_MOUNT="‘''${arg#*=}" ;;
      --postgres-secret=*) POSTGRES_SECRET="true" ;;
    esac
  done
}

put_secret_in_array() {
  local name="$1"
  local key="$2"
  local value="$3"

  check_env_var "PERSONAL_MONOREPO_LOCATION"
  local file_path="''${PERSONAL_MONOREPO_LOCATION}/terraform/vault-config/locals.tf"

  print_debug "Checking for secret named $name"
  local index
  index=$(hcledit -f "$file_path" select locals.secret_definitions --json 2>/dev/null \
    | jq -r '.[] | .name' | grep -n "^$name$" | cut -d: -f1)

  if [ -z "$index" ]; then
    print_debug "Secret $name not found, adding new entry"
    hcledit -f "$file_path" attribute append locals.secret_definitions "{ name = \"$name\", $key = \"$value\" }"
    print_info "Secret $name added to array"
  else
    index=$((index - 1))
    print_debug "Secret $name found at index $index, updating"
    hcledit -f "$file_path" attribute set locals.secret_definitions[$index]."$key" "$value"
    print_info "Secret $name updated"
  fi
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
  set_value="$(get_input "Set a value for this key? (y/n)" "n")"
  if [ "$set_value" = "y" ]; then
    key_value="$(get_input "Enter value for $key_name" "")"
  else
    key_value=""
  fi
  SECRET_KEYS+=("$key_name|$is_pg_password|$key_value")
}

main() {
  parse_args "$@"

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
    POSTGRES_SECRET="$(get_input "Does the secret contain postgres creds? (y/n)" "n")"
  fi

  print_debug "Collecting secret keys"
  SECRET_KEYS=()
  add_keys="$(get_input "Would you like to enter any secret keys? (y/n)" "n")"
  while [ "$add_keys" = "y" ]; do
    add_secret_key
    add_keys="$(get_input "Add another key? (y/n)" "n")"
  done

  # for entry in "‘''${SECRET_KEYS[@]}"; do
  #   key_name="$(cut -d'|' -f1 <<< "$entry")"
  #   is_pg_password="$(cut -d'|' -f2 <<< "$entry")"
  #   key_value="$(cut -d'|' -f3 <<< "$entry")"
  #   HCLEDIT_PATH="locals.secret_definitions.‘''${SECRET_NAME}.datahcl.‘''${key_name}"
  #   hcledit -f "$LOCAL_FILE" attribute set "$HCLEDIT_PATH.is_postgres_password" "$is_pg_password"
  #   if [ -n "$key_value" ]; then
  #     hcledit -f "$LOCAL_FILE" attribute set "$HCLEDIT_PATH.value" "$key_value"
  #   fi
  # done

  put_secret_in_array "$SECRET_NAME" "namespace" "$SECRET_NAMESPACE"
  #hcledit -f "$LOCAL_FILE" attribute set "locals.secret_definitions.''${SECRET_NAME}.mount" "$SECRET_MOUNT"
  #hcledit -f "$LOCAL_FILE" attribute set "locals.secret_definitions.''${SECRET_NAME}.postgres_secret" "$POSTGRES_SECRET"

  print_info "Secret definition for $SECRET_NAME added to locals.tf"
}

main "$@"

'';
in

{
  environment.systemPackages = [
    app-creator-add-terraform-secret
  ];
}