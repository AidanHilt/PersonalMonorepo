{ inputs, globals, pkgs, machine-config, lib, ...}:

let

nixos-key-retrieval = pkgs.writeShellScriptBin "nixos-key-retrieval" ''
SSH_PUBKEY=$(cat $1)
MACHINE_NAME=$2

if [ -z "$SSH_PUBKEY" ]; then
  echo "Error: Could not retrieve SSH public key from $1"
  exit 1
fi

echo "Retrieved SSH public key"

_modify-secrets-nix-let-statement "$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/secrets/secrets.nix" "$MACHINE_NAME-system" "$SSH_PUBKEY"

# Step 8: Change to secrets directory and run agenix
SECRETS_DIR="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/secrets"
echo "Changing to $SECRETS_DIR and running agenix -e..."
cd "$SECRETS_DIR"

if command -v agenix >/dev/null 2>&1; then
  agenix -r
  nix-commit
else
  echo "Error: agenix command not found in PATH"
  echo "Make sure agenix is installed and available"
  exit 1
fi
'';

in

{
  imports = [
    ../lib/default.nix
  ];

  environment.systemPackages = [
    nixos-key-retrieval
  ];
}