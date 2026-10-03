#!/usr/bin/env bash
# nix run .#stop-agent — shuts down the compose stack (both default and
# login profiles). Does NOT stop the host's native Ollama process,
# since other things on the host may depend on it (spec §3.3: Ollama is
# an external service this stack consumes, not one it owns).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$REPO_ROOT"

# --- Tear down pi's /nix/store overlay, if start-agent.sh set one up ------
# Only present when pkg-broker's default/isolated store backend was in
# use (PI_SANDBOX__PKGBROKER_HOST_STORE unset/0) -- the host-store-override
# backend binds /nix/store directly and has nothing of ours to unmount.
# This path must match the one start-agent.sh computes and mounts.
NIX_STORE_OVERLAY_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pi-sandbox/nix-store-overlay"
if mountpoint -q "$NIX_STORE_OVERLAY_DIR" 2>/dev/null; then
  echo "==> Unmounting pi's /nix/store overlay at $NIX_STORE_OVERLAY_DIR..."
  if ! sudo umount "$NIX_STORE_OVERLAY_DIR"; then
    echo "    WARNING: failed to unmount $NIX_STORE_OVERLAY_DIR -- leaving it mounted." >&2
    echo "    Unmount it manually later with: sudo umount \"$NIX_STORE_OVERLAY_DIR\"" >&2
  fi
fi

echo "==> Stopping compose stack..."
docker compose --profile login down --remove-orphans
echo "==> Done. (Ollama on the host was left running — stop it separately if desired.)"
#!/usr/bin/env bash
# nix run .#stop-agent — shuts down the compose stack (both default and
# login profiles). Does NOT stop the host's native Ollama process,
# since other things on the host may depend on it (spec §3.3: Ollama is
# an external service this stack consumes, not one it owns).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$REPO_ROOT"

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

echo "==> Done. (Ollama on the host was left running — stop it separately if desired.)"