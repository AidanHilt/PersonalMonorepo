{ inputs, globals, pkgs, machine-config, ...}:

let

get-username-from-machine-name = pkgs.writeShellScriptBin "get-username-from-machine-name" ''
if [ $# -ne 1 ]; then
  echo "Usage: $0 <machine-name>"
  exit 1
fi

MACHINE_NAME="$1"

# Check if PERSONAL_MONOREPO_LOCATION is set
if [ -z "$PERSONAL_MONOREPO_LOCATION" ]; then
  echo "Error: PERSONAL_MONOREPO_LOCATION environment variable is not set"
  exit 1
fi

MONO_FLAKE_PATH="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake"
MACHINES_PATH="$MONO_FLAKE_PATH/machines"

# Step 1: Check for machine folder in both architectures
MACHINE_PATH=""
if [ -d "$MACHINES_PATH/aarch64-linux/$MACHINE_NAME" ]; then
  MACHINE_PATH="$MACHINES_PATH/aarch64-linux/$MACHINE_NAME"
elif [ -d "$MACHINES_PATH/x86_64-linux/$MACHINE_NAME" ]; then
  MACHINE_PATH="$MACHINES_PATH/x86_64-linux/$MACHINE_NAME"
else
  echo "Error: Machine folder '$MACHINE_NAME' not found in aarch64-linux or x86_64-linux"
  exit 1
fi

# Step 2: Check for values.nix file
VALUES_FILE="$MACHINE_PATH/values.nix"
if [ ! -f "$VALUES_FILE" ]; then
  echo "Error: values.nix file not found at $VALUES_FILE"
  exit 1
fi

# Step 3: Extract username from values.nix
# Look for patterns like: username = "value"; or username="value";
USERNAME=$(grep -E '^\s*username\s*=\s*"[^"]*"' "$VALUES_FILE" | sed 's/.*"\([^"]*\)".*/\1/' | head -n1)

if [ -z "$USERNAME" ]; then
  echo "Error: Could not find username in $VALUES_FILE"
  echo "Looking for pattern: username = \"value\";"
  exit 1
fi

echo "$USERNAME"
'';

generate-homelab-node-files = pkgs.writeShellScriptBin "generate-homelab-node-files" ''
root=$(mktemp -d)
mkdir -p "$root/etc/ssh"
ssh-keygen -t ed25519 -f "$root/etc/ssh/ssh_host_ed25519_key" -N "" > /dev/null 2>&1
mkdir -p "$root/etc/rancher/rke2"
age -i ~/.ssh/id_ed25519 -d "$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/secrets/rke-config-$1.age" > "$root/etc/rancher/rke2/config.yaml"
echo $root | tr -d "\n"
'';

in

{
  environment.systemPackages = [
    generate-homelab-node-files
    get-username-from-machine-name
  ];
}