#!/usr/bin/env bash
# nix run .#start-agent
#
# Acceptance criterion (spec §11): a fresh host produces a working
# pi+proxy stack with no manual steps beyond providing credentials —
# this script starts Ollama (or verifies it), builds/loads images, and
# brings the compose stack up; `nix run .#stop-agent` tears it down.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Checking for a project directory to mount..."
mkdir -p "${PI_PROJECT_DIR:-./workspace}"

echo "==> Checking for a generated kubeconfig..."
if [ ! -f ./kube/agent-kubeconfig.yaml ]; then
  echo "    none found — run: nix run .#gen-kubeconfig" >&2
  echo "    (or place a pre-generated, dev/staging-scoped kubeconfig at ./kube/agent-kubeconfig.yaml)" >&2
  exit 1
fi

echo "==> Verifying Ollama is reachable natively on the host..."
OLLAMA_HOST_URL="${OLLAMA_HOST_URL:-http://127.0.0.1:11434}"
if ! curl -fsS --max-time 3 "$OLLAMA_HOST_URL/api/version" >/dev/null 2>&1; then
  cat >&2 <<EOF
    Ollama does not appear to be running at $OLLAMA_HOST_URL.
    This stack runs Ollama natively on the host, not in a container
    (spec §3.3 — GPU passthrough overhead). Start it first:
      macOS:  ollama serve   (or the Ollama.app menu-bar app)
      NixOS:  systemctl --user start ollama   (or: services.ollama.enable = true;)
    Then re-run this script.
EOF
  exit 1
fi
echo "    OK: Ollama is up."

echo "==> Building and loading pi/proxy images into the active Docker context..."
DOCKER_CTX="$(docker context show 2>/dev/null || echo 'default')"
echo "    Active Docker context: $DOCKER_CTX"
nix run .#load

echo "==> Starting docker compose stack (pi + proxy)..."
docker compose up -d proxy

cleanup() {
  echo "==> Session finished — tearing down the compose stack..."
  docker compose down --remove-orphans
}
trap cleanup EXIT

docker compose run --rm pi
