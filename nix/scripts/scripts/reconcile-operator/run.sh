#!/bin/bash
# @lib: printing-and-output
set -euo pipefail
shopt -s nullglob

show_help () {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Watches \$PERSONAL_MONOREPO_LOCATION/kubernetes/operators (plus the"
  echo "shared nix/, flake.nix, and flake.lock) for changes. On any change,"
  echo "rebuilds every operator, loads whichever images actually changed"
  echo "into a local kind cluster, and helm-upgrades them into a dev"
  echo "namespace. Uninstalls everything it installed when the loop exits."
  echo ""
  echo "OPTIONS:"
  echo "  --namespace <namespace>    Install every operator into this namespace instead of <operator>-dev"
  echo "  --cluster-name <name>      kind cluster name (default: kind)"
  echo "  --help, -h                 Show this help"
}

resolve_namespace () {
  local OPERATOR_NAME=$1
  if [[ -n "$NAMESPACE_OVERRIDE" ]]; then
    echo "$NAMESPACE_OVERRIDE"
  else
    echo "${OPERATOR_NAME}-dev"
  fi
}

sync_operator () {
  local OPERATOR_NAME=$1

  local IMAGE_PATH
  if ! IMAGE_PATH=$(nix build ".#${OPERATOR_NAME}-image" --no-link --print-out-paths); then
    print_error "Image build failed for ${OPERATOR_NAME}"
    return 1
  fi

  local CHART_PATH
  if ! CHART_PATH=$(nix build ".#${OPERATOR_NAME}-chart" --no-link --print-out-paths); then
    print_error "Chart build failed for ${OPERATOR_NAME}"
    return 1
  fi

  local IMAGE_STATE_FILE="${STATE_DIR}/${OPERATOR_NAME}.image"
  local CHART_STATE_FILE="${STATE_DIR}/${OPERATOR_NAME}.chart"
  local PREVIOUS_IMAGE_PATH
  PREVIOUS_IMAGE_PATH=$(cat "$IMAGE_STATE_FILE" 2>/dev/null || echo "")
  local PREVIOUS_CHART_PATH
  PREVIOUS_CHART_PATH=$(cat "$CHART_STATE_FILE" 2>/dev/null || echo "")

  # nix build returns the same store path when nothing relevant changed, so
  # this only redeploys operators actually affected by the edit.
  if [[ "$IMAGE_PATH" == "$PREVIOUS_IMAGE_PATH" && "$CHART_PATH" == "$PREVIOUS_CHART_PATH" ]]; then
    print_debug "${OPERATOR_NAME} unchanged"
    return 0
  fi

  printf '%s' "$IMAGE_PATH" > "$IMAGE_STATE_FILE"
  printf '%s' "$CHART_PATH" > "$CHART_STATE_FILE"

  print_debug "Loading ${OPERATOR_NAME} image into the local Docker daemon"
  nix run ".#${OPERATOR_NAME}-image.copyToDockerDaemon"
  docker tag "${OPERATOR_NAME}:latest" "${OPERATOR_NAME}:${DEV_TAG}"

  print_debug "Loading ${OPERATOR_NAME} image into kind cluster ${CLUSTER_NAME}"
  kind load docker-image "${OPERATOR_NAME}:${DEV_TAG}" --name "$CLUSTER_NAME"

  local NAMESPACE
  NAMESPACE=$(resolve_namespace "$OPERATOR_NAME")

  print_debug "Installing ${OPERATOR_NAME} into namespace ${NAMESPACE}"
  helm upgrade --install "$OPERATOR_NAME" "$CHART_PATH" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --set-string image.tag="$DEV_TAG" \
    --set-string image.pullPolicy=Never

  # kind load overwrites the image content in containerd under the same
  # tag, but a running pod won't notice on its own; force it to pick up
  # the freshly loaded bits.
  kubectl rollout restart "deployment/${OPERATOR_NAME}-controller-manager" --namespace "$NAMESPACE"
  kubectl rollout status "deployment/${OPERATOR_NAME}-controller-manager" --namespace "$NAMESPACE" --timeout=60s

  print_status "${OPERATOR_NAME} deployed to namespace ${NAMESPACE}"
}

sync_all () {
  local operator_dir
  for operator_dir in "${OPERATORS_DIR}"/*/; do
    [[ -f "${operator_dir}go.mod" ]] || continue
    local OPERATOR_NAME
    OPERATOR_NAME=$(basename "$operator_dir")
    sync_operator "$OPERATOR_NAME" || print_warning "Skipping ${OPERATOR_NAME} this cycle"
  done
}

cleanup () {
  local operator_dir
  for operator_dir in "${OPERATORS_DIR}"/*/; do
    [[ -f "${operator_dir}go.mod" ]] || continue
    local OPERATOR_NAME
    OPERATOR_NAME=$(basename "$operator_dir")
    local NAMESPACE
    NAMESPACE=$(resolve_namespace "$OPERATOR_NAME")
    helm uninstall "$OPERATOR_NAME" --namespace "$NAMESPACE" >/dev/null 2>&1 || true
  done
  rm -rf "$STATE_DIR"
  print_status "Dev loop stopped, releases uninstalled"
}

NAMESPACE_OVERRIDE=""
CLUSTER_NAME="kind"
SYNC_MODE=false
STATE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
    NAMESPACE_OVERRIDE=$2
    shift 2
    ;;
    --cluster-name)
    CLUSTER_NAME=$2
    shift 2
    ;;
    --state-dir)
    STATE_DIR=$2
    shift 2
    ;;
    --sync)
    SYNC_MODE=true
    shift
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

readonly NAMESPACE_OVERRIDE
readonly CLUSTER_NAME
readonly SYNC_MODE

if [[ -z "${PERSONAL_MONOREPO_LOCATION:-}" ]]; then
  print_error "PERSONAL_MONOREPO_LOCATION is not set"
  exit 1
fi

readonly MONOREPO_ROOT="${PERSONAL_MONOREPO_LOCATION}/kubernetes"
readonly OPERATORS_DIR="${MONOREPO_ROOT}/operators"
readonly NIX_DIR="${MONOREPO_ROOT}/nix"
readonly FLAKE_FILE="${MONOREPO_ROOT}/flake.nix"
readonly FLAKE_LOCK="${MONOREPO_ROOT}/flake.lock"
readonly DEV_TAG="dev"

if [[ "$SYNC_MODE" == true ]]; then
  readonly STATE_DIR
  sync_all
  exit 0
fi

if [[ -z "$STATE_DIR" ]]; then
  STATE_DIR=$(mktemp -d)
fi
readonly STATE_DIR

trap cleanup EXIT INT TERM

print_debug "Watching ${OPERATORS_DIR} for changes"
watchexec \
  --watch "$OPERATORS_DIR" \
  --watch "$NIX_DIR" \
  --watch "$FLAKE_FILE" \
  --watch "$FLAKE_LOCK" \
  --debounce 500 \
  -- "$0" --sync --state-dir "$STATE_DIR" --namespace "$NAMESPACE_OVERRIDE" --cluster-name "$CLUSTER_NAME"
