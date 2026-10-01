#!/usr/bin/env bash
# nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#start-agent
#
# Acceptance criterion (spec §11): a fresh host produces a working
# pi+proxy stack with no manual steps beyond providing credentials —
# this script builds/loads images and brings the compose stack up;
# `nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#stop-agent` tears it down.
set -euo pipefail

# --- Kubeconfig: always attempted, never required -------------------------
# We no longer hard-fail when no kubeconfig is present. If a scoped
# kubeconfig exists (default path below, or PI_KUBECONFIG_PATH), we layer
# compose.kube.yaml on top to mount it read-only into the `pi`
# container. If it's missing, we warn and continue without k8s access
# rather than blocking the whole stack on it.
KUBECONFIG_PATH="${PI_KUBECONFIG_PATH:-$HOME/.config/pi-sandbox/agent-kubeconfig.yaml}"
COMPOSE_FILES=(-f compose.yaml)

echo "==> Checking for a generated kubeconfig..."
if [ -f "$KUBECONFIG_PATH" ]; then
  echo "    found: $KUBECONFIG_PATH — enabling k8s access for this run."
  COMPOSE_FILES+=(-f compose.kube.yaml)
else
  cat >&2 <<EOF
    WARNING: no kubeconfig found at $KUBECONFIG_PATH.
    Continuing WITHOUT Kubernetes access for this run.
    To enable it, generate a scoped, dev/staging-only kubeconfig with:
      nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#gen-kubeconfig
    (or place a pre-generated one at $KUBECONFIG_PATH / set PI_KUBECONFIG_PATH)
EOF
fi

# --- Local Ollama support: DEPRECATED --------------------------------------
# The native-Ollama-on-host flow below is deprecated and disabled. We may
# revisit local AI in the future; leaving the logic here (commented out)
# rather than deleting it in case we do.
#
# echo "==> Verifying Ollama is reachable natively on the host..."
# OLLAMA_HOST_URL="${OLLAMA_HOST_URL:-http://127.0.0.1:11434}"
# if ! curl -fsS --max-time 3 "$OLLAMA_HOST_URL/api/version" >/dev/null 2>&1; then
# cat >&2 <<EOF
#     Ollama does not appear to be running at $OLLAMA_HOST_URL.
#     This stack runs Ollama natively on the host, not in a container
#     (spec §3.3 — GPU passthrough overhead). Start it first:
#       macOS:  ollama serve   (or the Ollama.app menu-bar app)
#       NixOS:  systemctl --user start ollama   (or: services.ollama.enable = true;)
#     Then re-run this script.
# EOF
# exit 1
# fi
# echo "    OK: Ollama is up."

cd "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack"

echo "==> Building and loading pi/proxy images into the active Docker context..."
DOCKER_CTX="$(docker context show 2>/dev/null || echo 'default')"
echo "    Active Docker context: $DOCKER_CTX"

override_flag=()
if [ -n "${PERSONAL_MONOREPO_LOCATION:-}" ] && [ -d "$PERSONAL_MONOREPO_LOCATION/nix/scripts" ]; then
  override_flag=(--override-input scripts "path:$PERSONAL_MONOREPO_LOCATION/nix/scripts")
  echo "==> Using local nix/scripts checkout at $PERSONAL_MONOREPO_LOCATION/nix/scripts"
fi

nix run "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#load" "${override_flag[@]}"

echo "==> Starting docker compose stack (pi + proxy)..."
docker compose "${COMPOSE_FILES[@]}" up -d proxy

cleanup() {
echo "==> Session finished — tearing down the compose stack..."
docker compose "${COMPOSE_FILES[@]}" down --remove-orphans
}
trap cleanup EXIT

docker compose "${COMPOSE_FILES[@]}" run --rm pi