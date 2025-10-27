{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };
modify-master-stack-values = (import ../lib/_modify-master-stack-values.nix { inherit pkgs; }).script;

app-creator-create-app = pkgs.writeShellScriptBin "app-creator-create-app" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}
source ${modify-master-stack-values}

show_help () {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Create a new app by editing the values file in the master-stack chart"
  echo ""
  echo "OPTIONS:"
  echo "--app-name: The name of the app"
  echo "--repo: The repository to read from"
  echo "--git-path: The path to read from in git repositories"
  echo "--chart-name: The name of the chart to read from the repository"
  echo "--version: The version tag to try and pull for the chart"
  echo "--namespace: The target namespace to deploy the app's resources"
  echo "--sync-options: ArgoCD sync options"
  echo "--sync-wave: A numerical representation of the ArgoCD sync wave to use"
  echo "--server-side-apply: Enable server-side apply"
  echo "--skip-default-values: Don't prompt the user for default values"
  echo "--skip-secure-values: Don't prompt the user for secure values"
}

app_type=""
app_name=""
repo=""
git_path=""
chart_name=""
version=""
namespace=""
sync_options=""
sync_wave=""
server_side_apply=""
input_default_values=""
input_secure_values=""

set_sync_options=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --app-name|-a)
    app_name="$2"
    shift 2
    ;;
    --repo|-r)
    repo="$2"
    shift 2
    ;;
    --chart-name|-c)
    chart_name="$2"
    app_type=2
    shift 2
    ;;
    --git-path|-g)
    git_path="$2"
    app_type=1
    shift 2
    ;;
    --version|-v)
    version="$2"
    shift 2
    ;;
    --namespace|-n)
    namespace="$2"
    shift 2
    ;;
    --sync-options|-s)
    sync_options="$2"
    set_sync_options="n"
    shift 2
    ;;
    --sync-wave|-w)
    sync_wave="$2"
    set_sync_options="n"
    shift 2
    ;;
    --server-side-apply)
    server_side_apply=true
    set_sync_options="n"
    shift 1
    ;;
    --skip-default-values)
    input_default_values=false
    shift 1
    ;;
    --skip-secure-values)
    input_secure_values=false
    shift 1
    ;;
    --help|-h)
    show_help
    exit 0
    ;;
    *)
    print_error "Unknown option: $1"
    exit 1
    ;;
  esac
done

echo "$app_name"

if [[ -z "$app_name" ]]; then
  read -p "Enter the name of your app: " app_name
fi

print_debug "App name set to: $app_name"

if [[ -z "$app_type" ]]; then
  echo "Select app type:"
  echo "1) Git-based"
  echo "2) External Helm chart"
  read -p "Enter your choice (1 or 2): " app_type
fi

YQ_STRING=".\"$app_name\".enabled=false"

if [[ "$app_type" == "1" ]]; then
  print_debug "Creating git-based app"

  if [[ -z "$repo" ]]; then
    read -p "Enter git repository URL (optional, press enter to skip): " repo
  fi

  if [[ -n "$repo" ]]; then
    print_debug "Git repository set to: $repo"
    YQ_STRING="$YQ_STRING | .\"$app_name\".repo = \"$repo\""
  fi

  if [[ -z "$git_path" ]]; then
    read -p "Enter git path: " git_path
    print_debug "Git path set to: $git_path"
    YQ_STRING="$YQ_STRING | .\"$app_name\".gitPath = \"$git_path\""
  fi

elif [[ "$app_type" == "2" ]]; then
  print_debug "Creating external Helm chart app"

  if [[ -z "$repo" ]]; then
    read -p "Enter Helm repository URL: " repo
    print_debug "Helm repository set to: $repo"
    YQ_STRING="$YQ_STRING | .\"$app_name\".repo = \"$repo\""
  fi

  if [[ -z "$chart_name" ]]; then
    read -p "Enter chart name: " chart_name
    print_debug "Chart name set to: $chart_name"
    YQ_STRING="$YQ_STRING | .\"$app_name\".chart = \"$chart_name\""
  fi

  if [[ -z "$version" ]]; then
    read -p "Enter chart version: " version
    print_debug "Chart version set to: $version"
    YQ_STRING="$YQ_STRING | .\"$app_name\".version = \"$version\""
  fi

else
  print_error "Invalid choice. Please select 1 or 2"
  exit 1
fi

if [[ -z "$namespace" ]]; then
  read -p "Enter namespace: " namespace
  print_debug "Namespace set to: $namespace"
  YQ_STRING="$YQ_STRING | .\"$app_name\".destinationNamespace = \"$namespace\""
fi

if [[ -z "$set_sync_options" ]]; then
  read -p "Do you want to set ArgoCD sync options? (y/n): " set_sync_options
fi

if [[ "$set_sync_options" == "y" ]]; then
  print_debug "Configuring ArgoCD sync options"

  if [[ -z "$sync_options" ]]; then
    read -p "Enter sync options (optional, press enter to skip): " sync_options
  fi

  if [[ -z "$sync_options" ]]; then
    print_debug "Sync options set to: $sync_options"
    YQ_STRING="$YQ_STRING | .\"$app_name\".syncOptions = \"$sync_options\""
  fi

  if [[ -z "$sync_wave" ]]; then
    read -p "Enter sync wave (optional, press enter to skip): " sync_wave
  fi

  if [[ -z "$sync_wave" ]]; then
    print_debug "Sync wave set to: $sync_wave"
    YQ_STRING="$YQ_STRING | .\"$app_name\".syncWave = \"$sync_wave\""
  fi

  if [[ -z "server_side_apply" ]]; then
    read -p "Enable serverSideApply? (y/n, default: n): " server_side_apply
  fi

  if [[ "$server_side_apply" == "y" ]]; then
    print_debug "serverSideApply enabled"
    YQ_STRING="$YQ_STRING | .\"$app_name\".serverSideApply = true"
  fi
fi


if [[ -z "$input_default_values" ]]; then
  read -p "Would you like to input default values? (y/n): " input_default_values
fi

if [[ "$input_default_values" == "y" ]]; then
  print_debug "Opening editor for default values"

  TEMP_DEFAULT_FILE=$(mktemp)
  echo "defaultValues: |" > "$TEMP_DEFAULT_FILE"

  ''${EDITOR:-vi} "$TEMP_DEFAULT_FILE"

  DEFAULT_VALUES_CONTENT=$(cat "$TEMP_DEFAULT_FILE")
  print_debug "Default values captured"

  TEMP_YAML_FILE=$(mktemp)
  echo "$DEFAULT_VALUES_CONTENT" > "$TEMP_YAML_FILE"
  YQ_STRING="$YQ_STRING | .\"$app_name\" += load(\"$TEMP_YAML_FILE\")"
fi

if [[ -z "$input_secure_values" ]]; then
  read -p "Would you like to input secure values to read from Vault?  (y/n): " input_secure_values
fi

if [[ "$input_secure_values" == "y" ]]; then
  print_debug "Opening editor for secure values (Vault references)"

  TEMP_SECURE_FILE=$(mktemp)
  echo "secureValues: |" > "$TEMP_SECURE_FILE"

  ''${EDITOR:-vi} "$TEMP_SECURE_FILE"

  SECURE_VALUES_CONTENT=$(cat "$TEMP_SECURE_FILE")
  print_debug "Secure values captured"

  TEMP_SECURE_YAML_FILE=$(mktemp)
  echo "$SECURE_VALUES_CONTENT" > "$TEMP_SECURE_YAML_FILE"
  YQ_STRING="$YQ_STRING | .\"$app_name\" += load(\"$TEMP_SECURE_YAML_FILE\")"
fi

print_debug "Constructed yq string: $YQ_STRING"

TARGET_FILE="$PERSONAL_MONOREPO_LOCATION/kubernetes/helm-charts/k8s-resources/master-stack/values.yaml"

echo "$YQ_STRING"

_modify-master-stack-values "$YQ_STRING" "$TARGET_FILE"

print_status "Application '$app_name' configuration added to master stack"
'';
in

{
  environment.systemPackages = [
    app-creator-create-app
  ];
}