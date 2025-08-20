{ inputs, globals, pkgs, machine-config, lib, ...}:

let
vault-unseal = pkgs.writeShellScriptBin "vault-unseal" ''
#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_debug() {
    echo -e "''${BLUE}[DEBUG]''${NC} $1"
}

check_vault_status() {
    print_status "Checking Vault status..."

    local status_output
    if ! status_output=$(vault status -format=json 2>/dev/null); then
        print_error "Failed to get Vault status. Is Vault server running at $VAULT_ADDR?"
        exit 1
    fi

    local sealed
    sealed=$(echo "$status_output" | jq -r '.sealed // true')

    if [[ "$sealed" == "false" ]]; then
        print_status "Vault is already unsealed!"
        return 0
    elif [[ "$sealed" == "true" ]]; then
        print_status "Vault is sealed - proceeding with unseal operation"
        return 1
    else
        print_error "Could not determine Vault seal status"
        exit 1
    fi
}

# Unseal vault with a key
unseal_with_key() {
    local key="$1"
    local key_name="$2"

    local unseal_output
    if ! unseal_output=$(vault operator unseal "$key" 2>/dev/null); then
        print_error "Failed to unseal with $key_name"
        return 1
    fi

    # Check if unsealed
    local sealed
    sealed=$(echo "$unseal_output" | grep -o 'Sealed[[:space:]]*[tf][a-z]*' | awk '{print $2}' || echo "true")

    if [[ "$sealed" == "false" ]]; then
        print_status "Vault successfully unsealed!"
        return 0
    else
        print_status "$key_name applied successfully (more keys needed)"
        return 1
    fi
}

# Main function
main() {
    print_status "Starting Vault unseal process..."

    check_vault_status

    echo
    print_status "Beginning unseal operations..."

    # Try to unseal with first key
    if unseal_with_key "$VAULT_UNSEAL_KEY_1" "VAULT_UNSEAL_KEY_1"; then
        echo
        print_status "Vault unseal process complete!"
        exit 0
    fi

    # Try to unseal with second key
    if unseal_with_key "$VAULT_UNSEAL_KEY_2" "VAULT_UNSEAL_KEY_2"; then
        echo
        print_status "Vault unseal process complete!"
        exit 0
    fi

    # If we reach here, vault is still sealed
    print_error "Vault is still sealed after using both keys. Additional keys may be required."

    # Show current status
    print_status "Current Vault status:"
    if ! vault status 2>/dev/null; then
        print_error "Failed to get final Vault status"
        exit 1
    fi

    exit 1
}

trap 'echo -e "\n''${YELLOW}[WARN]''${NC} Script interrupted"; exit 1' INT TERM

main "$@"
'';
in

{
  environment.systemPackages = [
    vault-unseal
  ];
}