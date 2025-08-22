{ inputs, globals, pkgs, machine-config, lib, ...}:

let
vault-initialize = pkgs.writeShellScriptBin "vault-initialize" ''
#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
  echo -e "''${GREEN}[INFO]''${NC} $1"
}

print_warning() {
  echo -e "''${YELLOW}[WARN]''${NC} $1"
}

print_error() {
  echo -e "''${RED}[ERROR]''${NC} $1"
}


main() {

  # Run vault operator init and capture output
  local vault_output
  if ! vault_output=$(vault operator init -key-shares=3 -key-threshold=2 -format=json 2>/dev/null); then
    print_error "Failed to initialize Vault. Is Vault already initialized?"
    exit 1
  fi

  print_status "Vault initialization successful!"

  if [[ -v ATILS_CURRENT_CONTEXT ]]; then
    local unseal_keys
    if ! unseal_keys=$(echo "$vault_output" | jq -r '.unseal_keys_b64[]' 2>/dev/null); then
      print_error "Failed to parse unseal keys from Vault output"
      exit 1
    fi

    local key_index=1
    while IFS= read -r encoded_key; do
      if [[ -n "$encoded_key" ]]; then

        # Decode the base64 key
        local decoded_key
        if ! decoded_key=$(echo "$encoded_key" | base64 -d 2>/dev/null | base64 -w 0); then
          print_error "Failed to decode unseal key $key_index"
          exit 1
        fi

        # Save using dotenvx
        local key_name="VAULT_UNSEAL_KEY_$key_index"

        dotenvx set "$key_name" "$decoded_key" -f "$ATILS_CONTEXTS_DIRECTORY/$ATILS_CURRENT_CONTEXT/.env"

        ((key_index++))
      fi
    done <<< "$unseal_keys"

    print_status "Processing root token..."
    local root_token
    if ! root_token=$(echo "$vault_output" | jq -r '.root_token' 2>/dev/null); then
      print_error "Failed to parse root token from Vault output"
      exit 1
    fi

    if [[ "$root_token" == "null" || -z "$root_token" ]]; then
      print_error "Root token is empty or null"
      exit 1
    fi

    # Save root token using dotenvx
    dotenvx set "VAULT_TOKEN" "$root_token" -f "$ATILS_CONTEXTS_DIRECTORY/$ATILS_CURRENT_CONTEXT/.env"

    print_status "Saved VAULT_TOKEN"
  else
    print_warning "No context is activated, so you're on your own for saving this"
    echo "$vault_output"
  fi

  print_status "Vault initialization complete!"
}
main "$@"
'';
in

{
  environment.systemPackages = [
  vault-initialize
  ];
}