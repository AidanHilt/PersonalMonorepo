{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

app-creator-add-postgres-config = pkgs.writeShellScriptBin "app-creator-add-postgres-config" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

show_help () {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Add postgres configuration (roles and DBs) to helm chart"
  echo "OPTIONS:"
  echo "  --username USERNAME Add a username to the postgres config. Can be provided multiple times"
  echo "  --database DB_NAME USERNAME Add a database to the postgres config. Can be provided multiple times"
}

declare -A USERS_TO_DBS

if [[ $# -eq 0 ]]; then
  while true; do
    read -p "Enter username (or leave blank to finish): " username

    if [[ -z "$username" ]]; then
      break
    fi

    USERS_TO_DBS["$username"]=""

    read -p "Would you like to make databases owned by $username? (y/n): " create_dbs

    if [[ "$create_dbs" =~ ^[Yy]$ ]]; then
      while true; do
        read -p "Enter database name (or leave blank to finish): " dbname

        if [[ -z "$dbname" ]]; then
          break
        fi

        if [[ -z "''${USERS_TO_DBS[$username]}" ]]; then
          USERS_TO_DBS["$username"]="$dbname"
        else
          USERS_TO_DBS["$username"]="''${USERS_TO_DBS[$username]} $dbname"
        fi
      done
    fi
  done
else
  while [[ $# -gt 0 ]]; do
    case $1 in
      --username)
        username="$2"
        USERS_TO_DBS["$username"]=""
        shift 2
        ;;
      --database)
        dbname="$2"
        owner="$3"
        if [[ -z "''${USERS_TO_DBS[$owner]}" ]]; then
          USERS_TO_DBS["$owner"]="$dbname"
        else
          USERS_TO_DBS["$owner"]="''${USERS_TO_DBS[$owner]} $dbname"
        fi
        shift 3
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
fi

VALUES_FILE="$PERSONAL_MONOREPO_LOCATION/kubernetes/helm-charts/k8s-resources/postgres-config/values.yaml"

for user in "''${!USERS_TO_DBS[@]}"; do
  print_debug "Processing user: $user"

  yq eval ".[] | select(. != null) | key" "$VALUES_FILE" | while read -r top_level_key; do
    yq eval -i ".$top_level_key.roles += [\"$user\"]" "$VALUES_FILE"
    print_debug "Added role $user to $top_level_key"
  done

  if [[ -n "''${USERS_TO_DBS[$user]}" ]]; then
    for db in ''${USERS_TO_DBS[$user]}; do
      print_debug "Processing database: $db with owner: $user"

      yq eval ".[] | select(. != null) | key" "$VALUES_FILE" | while read -r top_level_key; do
        yq eval -i ".$top_level_key.databases.\"$db\".owner = \"$user\"" "$VALUES_FILE"
        print_debug "Added database $db to $top_level_key"
      done
    done
  fi
done

print_status "Successfully updated postgres configuration"
'';
in

{
  environment.systemPackages = [
    app-creator-add-postgres-config
  ];
}