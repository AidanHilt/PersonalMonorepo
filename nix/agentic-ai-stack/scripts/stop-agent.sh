#!/usr/bin/env bash
# nix run .#stop-agent — shuts down the compose stack (both default and
# login profiles). Does NOT stop the host's native Ollama process,
# since other things on the host may depend on it (spec §3.3: Ollama is
# an external service this stack consumes, not one it owns).
set -euo pipefail

# Under `nix run` this script lives in the Nix store, so a path derived from
# $BASH_SOURCE has no compose.yaml next to it. Same lookup as start-agent.sh:
# use the monorepo checkout, and fall back to the script-relative path for
# running it straight out of the repo.
STACK_DIR="${PERSONAL_MONOREPO_LOCATION:+$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack}"
if [ -z "$STACK_DIR" ] || [ ! -f "$STACK_DIR/compose.yaml" ]; then
  STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
fi
if [ ! -f "$STACK_DIR/compose.yaml" ]; then
  echo "error: can't find compose.yaml (tried \$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack and the script's parent dir)." >&2
  echo "       Set PERSONAL_MONOREPO_LOCATION and re-run." >&2
  exit 1
fi
cd "$STACK_DIR"

# compose.yaml requires this variable at parse time (start-agent.sh exports
# the real value). `down` doesn't use it, so a placeholder is enough here.
export PI_SANDBOX__NIX_STORE_SOURCE="${PI_SANDBOX__NIX_STORE_SOURCE:-/nonexistent-stop-agent-placeholder}"

echo "==> Stopping compose stack..."
# --remove-orphans also stops nix-store-mounter (defined only in
# compose.nixstore-overlay.yaml), which unmounts its overlay on SIGTERM.
docker compose --profile login down --remove-orphans

# --- Backstop: unmount any merged-store overlay left on the host ----------
# Normally nix-store-mounter's own shutdown trap already removed it (the
# umount propagates to the host). This catches a killed/crashed mounter, and
# the old host-side overlay from the previous design. Paths must match
# start-agent.sh.
MERGED_DIR="${PI_SANDBOX__NIX_STORE_MERGED_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/pi-sandbox/nix-store-merged}"
OLD_OVERLAY_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pi-sandbox/nix-store-overlay"
for dir in "$MERGED_DIR" "$OLD_OVERLAY_DIR"; do
  # Loop: a crash-and-restart can leave several stacked mounts.
  while mountpoint -q "$dir" 2>/dev/null; do
    echo "==> Unmounting leftover store overlay at $dir..."
    if ! sudo umount "$dir"; then
      echo "    WARNING: failed to unmount $dir -- leaving it mounted." >&2
      echo "    Unmount it manually later with: sudo umount \"$dir\"" >&2
      break
    fi
  done
done

echo "==> Done."