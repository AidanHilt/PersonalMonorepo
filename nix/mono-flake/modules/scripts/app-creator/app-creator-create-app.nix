{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };
modify-master-stack-values = (import ../lib/_modify-master-stack-values.nix { inherit pkgs; }).script;

app-creator-create-app = pkgs.writeShellScriptBin "app-creator-create-app" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}
source ${modify-master-stack-values}

# show_help () {
#   echo "Usage: $0 [OPTIONS]"
#   echo ""
#   # Description goes here
#   echo ""
#   echo ""
#   echo "OPTIONS:"
# }

# while [[ $# -gt 0 ]]; do
#   case $1 in
#     --<>|-<>)

#     shift 2
#     ;;
#     --help|-h)
#     show_help
#     exit 0
#     ;;
#     *)
#     print_error "Unknown option: $1"
#     exit 1
#     ;;
#   esac
# done

read -p "Enter the name of your app: " app_name

print_debug "App name set to: $app_name"

echo "Select app type:"
echo "1) Git-based"
echo "2) External Helm chart"
read -p "Enter your choice (1 or 2): " app_type

YQ_STRING=".\"$app_name\".enabled=false"

if [[ "$app_type" == "1" ]]; then
  print_debug "Creating git-based app"

  read -p "Enter git repository URL (optional, press enter to skip): " git_repo

  if [[ -n "$git_repo" ]]; then
    print_debug "Git repository set to: $git_repo"
    YQ_STRING="$YQ_STRING | .\"$app_name\".repo = \"$git_repo\""
  fi

  read -p "Enter git path: " git_path
  print_debug "Git path set to: $git_path"
  YQ_STRING="$YQ_STRING | .\"$app_name\".gitPath = \"$git_path\""

elif [[ "$app_type" == "2" ]]; then
  print_debug "Creating external Helm chart app"

  read -p "Enter Helm repository URL: " helm_repo
  print_debug "Helm repository set to: $helm_repo"
  YQ_STRING="$YQ_STRING | .\"$app_name\".repo = \"$helm_repo\""

  read -p "Enter chart name: " chart_name
  print_debug "Chart name set to: $chart_name"
  YQ_STRING="$YQ_STRING | .\"$app_name\".chart = \"$chart_name\""

  read -p "Enter chart version: " chart_version
  print_debug "Chart version set to: $chart_version"
  YQ_STRING="$YQ_STRING | .\"$app_name\".version = \"$chart_version\""

else
  print_error "Invalid choice. Please select 1 or 2"
  exit 1
fi

read -p "Enter namespace: " namespace
print_debug "Namespace set to: $namespace"
YQ_STRING="$YQ_STRING | .\"$app_name\".destinationNamespace = \"$namespace\""

read -p "Do you want to set ArgoCD sync options? (y/n): " set_sync_options

if [[ "$set_sync_options" == "y" ]]; then
  print_debug "Configuring ArgoCD sync options"

  read -p "Enter sync options (optional, press enter to skip): " sync_options

  if [[ -n "$sync_options" ]]; then
    print_debug "Sync options set to: $sync_options"
    YQ_STRING="$YQ_STRING | .\"$app_name\".syncOptions = \"$sync_options\""
  fi

  read -p "Enter sync wave (optional, press enter to skip): " sync_wave

  if [[ -n "$sync_wave" ]]; then
    print_debug "Sync wave set to: $sync_wave"
    YQ_STRING="$YQ_STRING | .\"$app_name\".syncWave = $sync_wave"
  fi

  read -p "Enable serverSideApply? (y/n, default: n): " server_side_apply

  if [[ "$server_side_apply" == "y" ]]; then
    print_debug "serverSideApply enabled"
    YQ_STRING="$YQ_STRING | .\"$app_name\".serverSideApply = true"
  fi
fi

read -p "Would you like to input default values? (y/n): " input_default_values

if [[ "$input_default_values" == "y" ]]; then
  print_debug "Opening editor for default values"

  TEMP_DEFAULT_FILE=$(mktemp)
  echo "defaultValues:" > "$TEMP_DEFAULT_FILE"

  ''${EDITOR:-vi} "$TEMP_DEFAULT_FILE"

  DEFAULT_VALUES_CONTENT=$(cat "$TEMP_DEFAULT_FILE")
  print_debug "Default values captured"

  TEMP_YAML_FILE=$(mktemp)
  echo "$DEFAULT_VALUES_CONTENT" > "$TEMP_YAML_FILE"
  YQ_STRING="$YQ_STRING | .\"$app_name\".defaultValues = load(\"$TEMP_YAML_FILE\").defaultValues"
fi

read -p "Would you like to input secure values (for Vault integration)? (y/n): " input_secure_values

if [[ "$input_secure_values" == "y" ]]; then
  print_debug "Opening editor for secure values (Vault references)"

  TEMP_SECURE_FILE=$(mktemp)
  echo "secureValues:" > "$TEMP_SECURE_FILE"

  ''${EDITOR:-vi} "$TEMP_SECURE_FILE"

  SECURE_VALUES_CONTENT=$(cat "$TEMP_SECURE_FILE")
  print_debug "Secure values captured"

  TEMP_SECURE_YAML_FILE=$(mktemp)
  echo "$SECURE_VALUES_CONTENT" > "$TEMP_SECURE_YAML_FILE"
  YQ_STRING="$YQ_STRING | .\"$app_name\".secureValues = load(\"$TEMP_SECURE_YAML_FILE\").secureValues"
fi

print_debug "Constructed yq string: $YQ_STRING"

TARGET_FILE="$PERSONAL_MONOREPO_LOCATION/kubernetes/helm-charts/k8s-resources/master-stack/values.yaml"

_modify-master-stack-values "$YQ_STRING" "$TARGET_FILE"

print_status "Application '$app_name' configuration added to master stack"
'';
in

{
  environment.systemPackages = [
    app-creator-create-app
  ];
}