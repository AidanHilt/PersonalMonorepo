{ inputs, globals, pkgs, machine-config, ...}:

let

nixos-key-retrieval = pkgs.writeShellScriptBin "nixos-key-retrieval" ''
SSH_PUBKEY=$(cat $1)
MACHINE_NAME=$2

if [ -z "$SSH_PUBKEY" ]; then
  echo "Error: Could not retrieve SSH public key from $1"
  exit 1
fi

echo "Retrieved SSH public key"

# Step 5: Create the formatted string
FORMATTED_STRING="''${MACHINE_NAME}-system = \"$SSH_PUBKEY\";"

# Step 6: Copy to clipboard
# Try different clipboard commands based on what's available
if command -v pbcopy >/dev/null 2>&1; then
  # macOS
  echo "$FORMATTED_STRING" | pbcopy
  echo "Copied to clipboard using pbcopy"
elif command -v xclip >/dev/null 2>&1; then
  # Linux with xclip
  echo "$FORMATTED_STRING" | xclip -selection clipboard
  echo "Copied to clipboard using xclip"
elif command -v wl-copy >/dev/null 2>&1; then
  # Wayland
  echo "$FORMATTED_STRING" | wl-copy
  echo "Copied to clipboard using wl-copy"
else
  echo "Warning: No clipboard utility found (pbcopy, xclip, wl-copy)"
  echo "The formatted string is: $FORMATTED_STRING"
fi

# Step 7: Open secrets.nix
SECRETS_FILE="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/secrets/secrets.nix"
echo "Opening $SECRETS_FILE..."

# Try different editors based on what's available and environment
if [ -n "$EDITOR" ]; then
  $EDITOR "$SECRETS_FILE"
elif command -v code >/dev/null 2>&1; then
  code "$SECRETS_FILE"
elif command -v vim >/dev/null 2>&1; then
  vim "$SECRETS_FILE"
elif command -v nano >/dev/null 2>&1; then
  nano "$SECRETS_FILE"
else
  echo "Warning: No suitable editor found. Please manually edit: $SECRETS_FILE"
  echo "Add this line: $FORMATTED_STRING"
fi

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
  environment.systemPackages = [
    nixos-key-retrieval
  ];
}