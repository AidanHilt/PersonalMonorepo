{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

keepass-retrieve-secret = pkgs.writeShellScriptBin "keepass-retrieve-secret" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

key_name="Password"
secret_path=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --key-name)
      key_name="$2"
      shift 2
      ;;
    --secret-path)
      secret_path="$2"
      shift 2
      ;;
    *)
      print_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$secret_path" ]]; then
  print_error "--secret-path is required"
  exit 1
fi

if [[ ! -v KEEPASS_PASSWORD ]]; then
  print_debug "KEEPASS_PASSWORD not set, decrypting..."
  eval $(age -i ~/.ssh/id_ed25519 -d "$ATILS_CONFIG_DIRECTORY/keepass-password")
fi

KEY_NAME="$key_name"
SECRET_PATH="$secret_path"

print_debug "Retrieving $KEY_NAME from $SECRET_PATH"

result=$(echo "$KEEPASS_PASSWORD" | keepassxc-cli show -q -s -k "$KEEPASS_KEY_FILE_PATH" -a "$KEY_NAME" "$KEEPASS_DB_PATH" "$SECRET_PATH")

echo "$result"
'';
in

{
  environment.systemPackages = [
    keepass-retrieve-secret
  ];

  environment.variables = {
    KEEPASS_KEY_FILE_PATH = "${machine-config.userBase}/${machine-config.username}/KeePass/MasterDatabase.key";
    KEEPASS_DB_PATH = "${machine-config.userBase}/${machine-config.username}/KeePass/MasterDatabase.kdbx";
  };
}