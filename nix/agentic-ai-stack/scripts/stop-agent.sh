#!/usr/bin/env bash
# nix run .#stop-agent — shuts down the compose stack (both default and
# login profiles). Does NOT stop the host's native Ollama process,
# since other things on the host may depend on it (spec §3.3: Ollama is
# an external service this stack consumes, not one it owns).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Stopping compose stack..."
docker compose --profile login down --remove-orphans
echo "==> Done. (Ollama on the host was left running — stop it separately if desired.)"
