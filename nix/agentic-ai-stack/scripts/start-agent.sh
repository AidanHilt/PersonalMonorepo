#!/bin/bash

# @lib: printing-and-output

set -euo pipefail

show_help () {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Build and start the pi + proxy compose stack."
  echo ""
  echo ""
  echo "OPTIONS:"
  echo "  --kubeconfig-path <path>   Path to a scoped kubeconfig"
  echo "  --monorepo-path <path>     Path to the monorepo mounted as /workspace and containing the agentic-ai-stack flake"
  echo "  --help, -h                 Show this help message"
}

KUBECONFIG_PATH="${PI_KUBECONFIG_PATH:-${HOME}/.config/pi-sandbox/agent-kubeconfig.yaml}"
MONOREPO_PATH="${PERSONAL_MONOREPO_LOCATION:-./workspace}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kubeconfig-path)
    KUBECONFIG_PATH="$2"
    shift 2
    ;;
    --monorepo-path)
    MONOREPO_PATH="$2"
    shift 2
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

readonly KUBECONFIG_PATH
readonly MONOREPO_PATH

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

if [[ -f "${KUBECONFIG_PATH}" ]]; then
  print_debug "Found kubeconfig at ${KUBECONFIG_PATH}, enabling Kubernetes access."
  COMPOSE_ARGS=(-f "${REPO_ROOT}/docker-compose.yml" -f "${REPO_ROOT}/docker-compose.kube.yml")
else
  print_warning "No kubeconfig found at ${KUBECONFIG_PATH}, continuing without Kubernetes access."
  COMPOSE_ARGS=(-f "${REPO_ROOT}/docker-compose.yml")
fi
readonly -a COMPOSE_ARGS

# Local Ollama support is deprecated; we may revisit local AI in the future.
# OLLAMA_HOST_URL="${OLLAMA_HOST_URL:-http://127.0.0.1:11434}"
# if ! curl -fsS --max-time 3 "${OLLAMA_HOST_URL}/api/version" >/dev/null 2>&1; then
#   print_error "Ollama does not appear to be running at ${OLLAMA_HOST_URL}."
#   exit 1
# fi
# print_debug "Ollama is reachable at ${OLLAMA_HOST_URL}."

mkdir -p "${MONOREPO_PATH}"

DOCKER_CONTEXT="$(docker context show 2>/dev/null || echo "default")"
readonly DOCKER_CONTEXT
print_debug "Active Docker context: ${DOCKER_CONTEXT}"

print_debug "Building and loading pi/proxy images."
nix run "${MONOREPO_PATH}/nix/agentic-ai-stack#load" --system aarch64-linux

cleanup () {
  print_debug "Tearing down the compose stack."
  PERSONAL_MONOREPO_LOCATION="${MONOREPO_PATH}" docker compose "${COMPOSE_ARGS[@]}" down --remove-orphans
}
trap cleanup EXIT

print_debug "Starting the proxy container."
PERSONAL_MONOREPO_LOCATION="${MONOREPO_PATH}" docker compose "${COMPOSE_ARGS[@]}" up -d proxy

print_status "Stack is up, starting pi."
PERSONAL_MONOREPO_LOCATION="${MONOREPO_PATH}" docker compose "${COMPOSE_ARGS[@]}" run --rm pi