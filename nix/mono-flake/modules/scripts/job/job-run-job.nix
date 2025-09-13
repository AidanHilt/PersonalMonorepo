{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

job-run-job = pkgs.writeShellScriptBin "job-run-job" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

#!/bin/bash

set -euo pipefail

get_job_names() {
  local job_dirs=()
  for dir in "$ATILS_JOB_DIR"/*; do
    if [[ -d "$dir" && "$(basename "$dir")" != "template" ]]; then
      job_dirs+=("$(basename "$dir")")
    fi
  done
  printf '%s\n' "''${job_dirs[@]}"
}

JOB_NAME="''${1:-}"
shift 2>/dev/null || true

NAMESPACE=""
HELM_ARGS=()
PARSING_HELM_ARGS=false

while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--" ]]; then
    PARSING_HELM_ARGS=true
    shift
    continue
  fi

  if $PARSING_HELM_ARGS; then
    HELM_ARGS+=("$1")
  else
    case $1 in
      --namespace)
        NAMESPACE="$2"
        shift 2
        ;;
      *)
        print_error "Unknown option: $1"
        exit 1
        ;;
    esac
  fi
  shift
done

if [[ -z "$NAMESPACE" ]]; then
  NAMESPACE=$(kubectl config view --minify --output 'jsonpath={..namespace}')
  if [[ -z "$NAMESPACE" ]]; then
    NAMESPACE="default"
  fi
fi

if [[ -z "$JOB_NAME" ]]; then
  readarray -t JOB_OPTIONS < <(get_job_names)
  if [[ ''${#JOB_OPTIONS[@]} -eq 0 ]]; then
    print_error "No job directories found in $ATILS_JOB_DIR"
    exit 1
  fi
  get_user_selection JOB_OPTIONS JOB_NAME
fi

JOB_DIR="$ATILS_JOB_DIR/$JOB_NAME"
if [[ ! -d "$JOB_DIR" ]]; then
  print_error "Job directory $JOB_DIR does not exist"
  exit 1
fi

CHART_YAML="$JOB_DIR/Chart.yaml"
if [[ ! -f "$CHART_YAML" ]]; then
  print_error "Chart.yaml not found in $JOB_DIR"
  exit 1
fi

CHART_NAME=$(yq eval '.name' "$CHART_YAML")
RELEASE_NAME="$CHART_NAME"

print_status "Installing helm chart $CHART_NAME as release $RELEASE_NAME"
helm install "$RELEASE_NAME" "$JOB_DIR" --namespace "$NAMESPACE" "''${HELM_ARGS[@]}"

print_status "Waiting for job $CHART_NAME to complete in namespace $NAMESPACE"
kubectl wait --for=condition=complete job/"$CHART_NAME" --namespace "$NAMESPACE" --timeout=600s

JOB_STATUS=$(kubectl get job "$CHART_NAME" --namespace "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')

if [[ "$JOB_STATUS" == "True" ]]; then
  print_status "Job completed successfully, uninstalling chart"
  helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE"
else
  FAILED_STATUS=$(kubectl get job "$CHART_NAME" --namespace "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}')
  if [[ "$FAILED_STATUS" == "True" ]]; then
    print_error "Job failed, leaving chart installed for debugging"
    exit 1
  else
    print_warning "Job status unclear, leaving chart installed for debugging"
    exit 1
  fi
fi
'';
in

{
  environment.systemPackages = [
    job-run-job
  ];
}