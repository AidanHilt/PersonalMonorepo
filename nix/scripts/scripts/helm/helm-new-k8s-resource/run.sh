#!/bin/bash

set -euo pipefail

# @lib: printing-and-output
# @lib: args-and-help
# @lib: env-checks

CHART_NAME=""
RESOURCE_TYPE=""

args_value "" "--chart-name" CHART_NAME "NAME" "Name of the helm chart to create"
args_value "" "--resource-type" RESOURCE_TYPE "TYPE" "Resource type to substitute into the template"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

if [[ -z "$CHART_NAME" ]]; then
  read -rp "Enter chart name: " CHART_NAME
fi

if [[ -z "$CHART_NAME" ]]; then
  print_error "Chart name cannot be empty"
  exit 1
fi

require_monorepo

SOURCE_DIR="${PERSONAL_MONOREPO_LOCATION}/kubernetes/helm-charts/templates/k8s-resources"
DEST_DIR="${PERSONAL_MONOREPO_LOCATION}/kubernetes/helm-charts/k8s-resources/${CHART_NAME}"

if [[ ! -d "$SOURCE_DIR" ]]; then
  print_error "Source directory does not exist: $SOURCE_DIR"
  exit 1
fi

print_debug "Creating destination directory: $DEST_DIR"
mkdir -p "$DEST_DIR"

print_debug "Copying files from $SOURCE_DIR to $DEST_DIR"
cp -r "$SOURCE_DIR"/* "$DEST_DIR"

if [[ -z "$RESOURCE_TYPE" ]]; then
  read -rp "Enter resource type: " RESOURCE_TYPE
fi

if [[ -z "$RESOURCE_TYPE" ]]; then
  print_error "Resource type cannot be empty"
  exit 1
fi

export CHART_NAME
export RESOURCE_TYPE

print_debug "Running envsubst on all files in $DEST_DIR"
find "$DEST_DIR" -type f | while read -r FILE; do
  envsubst <"$FILE" >"$FILE.tmp"
  mv "$FILE.tmp" "$FILE"
  print_debug "Processed: $FILE"
done

print_status "Helm chart template created successfully for chart: $CHART_NAME"
