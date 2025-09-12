{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

job-create-job = pkgs.writeShellScriptBin "job-create-job" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

JOB_NAME=""
JOB_DESCRIPTION="A kubernetes job"

usage() {
  echo "Usage: $0 --job-name <name> [--description <description>]"
  echo "  --job-name    Required. Name of the job"
  echo "  --description   Optional. Description of the job (default: 'A kubernetes job')"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --job-name)
      if [[ -n "''${  2:-}" ]]; then
        JOB_NAME="$2"
        shift 2
      else
        echo "Error: --job-name requires a value"
        usage
      fi
      ;;
    --description)
      if [[ -n "''${  2:-}" ]]; then
        JOB_DESCRIPTION="$2"
        shift 2
      else
        echo "Error: --description requires a value"
        usage
      fi
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: Unknown option $1"
      usage
      ;;
  esac
done

if [[ -z "$JOB_NAME" ]]; then
  echo "Error: --job-name is required"
  usage
fi

export JOB_NAME
export JOB_DESCRIPTION

if [[ ! -d "$ATILS_JOB_DIR/template" ]]; then
  print_error "Error: Template directory $ATILS_JOB_DIR/template does not exist"
  exit 1
fi

DEST_DIR="$ATILS_JOB_DIR/$JOB_NAME"

cp -r "$ATILS_JOB_DIR/template" "$DEST_DIR"

if [[ ! -f "$DEST_DIR/Chart.yaml" ]]; then
  print_error "Copy failed. Exiting"
  exit 1
else
  echo "Running envsubst on Chart.yaml..."
  TEMP_FILE=$(mktemp)

  envsubst < "$DEST_DIR/Chart.yaml" > "$TEMP_FILE"

  mv "$TEMP_FILE" "$DEST_DIR/Chart.yaml"

  echo "Environment variable substitution completed"
fi

echo "Job setup completed successfully!"
echo "Job Name: $JOB_NAME"
echo "Description: $JOB_DESCRIPTION"
echo "Location: $DEST_DIR"
'';
in

{
  environment.systemPackages = [
    job-create-job
  ];
}