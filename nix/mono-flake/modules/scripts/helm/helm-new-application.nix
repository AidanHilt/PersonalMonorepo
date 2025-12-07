{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

helm-new-application = pkgs.writeShellScriptBin "helm-new-application" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

show_help() {
  "Usage: $0 [OPTIONS]"
  echo ""
  echo "OPTIONS:"
  echo "  --chart-name NAME    Name of the helm chart to create"
  echo "  --help               Show this help message"
}

CHART_NAME=""
RESOURCE_TYPE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --chart-name)
      CHART_NAME="$2"
      shift 2
      ;;
    --help)
      show_help
      exit 0
      ;;
    *)
      print_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$CHART_NAME" ]]; then
  read -p "Enter chart name: " CHART_NAME
fi

if [[ -z "$CHART_NAME" ]]; then
  print_error "Chart name cannot be empty"
  exit 1
fi

SOURCE_DIR="''${PERSONAL_MONOREPO_LOCATION}/kubernetes/helm-charts/templates/application"
DEST_DIR="''${PERSONAL_MONOREPO_LOCATION}/kubernetes/helm-charts/applications/''${CHART_NAME}"

if [[ ! -d "$SOURCE_DIR" ]]; then
  print_error "Source directory does not exist: $SOURCE_DIR"
  exit 1
fi

print_debug "Creating destination directory: $DEST_DIR"
mkdir -p "$DEST_DIR"

print_debug "Copying files from $SOURCE_DIR to $DEST_DIR"
cp -r "$SOURCE_DIR"/* "$DEST_DIR"

export CHART_NAME
export UNDERSCORE="\$_"
export name="\$name"

print_debug "Running envsubst on all files in $DEST_DIR"
find "$DEST_DIR" -type f | while read -r FILE; do
  envsubst < "$FILE" > "$FILE.tmp"
  mv "$FILE.tmp" "$FILE"
  print_debug "Processed: $FILE"
done

print_status "Helm chart template created successfully for chart: $CHART_NAME"
'';
in

{
  environment.systemPackages = [
    helm-new-application
  ];
}