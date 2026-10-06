#!/usr/bin/env bash
# nix run .#stop-agent — shuts down the compose stack (both default and
# login profiles). Does NOT stop the host's native Ollama process,
# since other things on the host may depend on it (spec §3.3: Ollama is
# an external service this stack consumes, not one it owns).
set -euo pipefail

# --- Persistence: pkg-bin / nix-store / proxy-domains volumes -------------
# Same flags/env vars/defaults as start-agent.sh (see its own header
# comment and README.md for the full writeup): pkg-bin=ephemeral,
# nix-store=persistent, proxy-domains=ephemeral. A CLI flag always
# overrides its matching PI_SANDBOX__PERSIST_* env var. pi-auth/pi-sessions
# are NEVER touched by this script.
PERSIST_PKGS_FLAG=""
PERSIST_STORE_FLAG=""
PERSIST_DOMAINS_FLAG=""

print_help() {
  cat <<'EOF'
Usage: stop-agent.sh [FLAGS]

Tears down the pi+proxy+pkg-broker compose stack (nix run .#stop-agent),
then removes any non-persisted volumes (pkg-bin/nix-store/proxy-domains)
left behind -- see start-agent.sh --help / README.md for the full
persistence model. Flags here only affect which volumes get removed; they
don't change anything about how the stack was started.

Flags:
  --persist-pkgs             Keep the pkg-bin volume instead of removing
                            it. Default: off (ephemeral).
  --no-persist-store         Remove the nix-store volume instead of
                            keeping it. Default: on (persistent).
  --persist-domains          Keep the proxy-domains volume (runtime
                            request-domain grants) instead of removing
                            it. Default: off (ephemeral).
  --help, -h                  Show this help and exit. No docker/sudo/nix
                            work is performed.

Environment variables (a CLI flag above always overrides the matching one):
  PI_SANDBOX__PERSIST_PKGS=0|1          Default: 0.
  PI_SANDBOX__PERSIST_STORE=0|1         Default: 1.
  PI_SANDBOX__PERSIST_DOMAINS=0|1       Default: 0.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      print_help
      exit 0
      ;;
    --persist-pkgs)
      PERSIST_PKGS_FLAG=1
      shift
      ;;
    --no-persist-store)
      PERSIST_STORE_FLAG=0
      shift
      ;;
    --persist-domains)
      PERSIST_DOMAINS_FLAG=1
      shift
      ;;
    *)
      echo "error: unrecognized argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -n "$PERSIST_PKGS_FLAG" ]; then
  PERSIST_PKGS="$PERSIST_PKGS_FLAG"
else
  PERSIST_PKGS="${PI_SANDBOX__PERSIST_PKGS:-0}"
fi
if [ -n "$PERSIST_STORE_FLAG" ]; then
  PERSIST_STORE="$PERSIST_STORE_FLAG"
else
  PERSIST_STORE="${PI_SANDBOX__PERSIST_STORE:-1}"
fi
if [ -n "$PERSIST_DOMAINS_FLAG" ]; then
  PERSIST_DOMAINS="$PERSIST_DOMAINS_FLAG"
else
  PERSIST_DOMAINS="${PI_SANDBOX__PERSIST_DOMAINS:-0}"
fi
echo "==> Persistence: pkg-bin=$( [ "$PERSIST_PKGS" = "1" ] && echo persistent || echo ephemeral ), nix-store=$( [ "$PERSIST_STORE" = "1" ] && echo persistent || echo ephemeral ), proxy-domains=$( [ "$PERSIST_DOMAINS" = "1" ] && echo persistent || echo ephemeral )"

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

# --- Removing non-persisted volumes ---------------------------------------
# pkg-bin/nix-store/proxy-domains volume names/declarations don't vary
# between any of the opt-in compose overrides (compose.pkgbroker-host-store.yaml,
# compose.workspace.yaml, etc.) -- only the base compose.yaml needs parsing
# to resolve their actual (project-name-prefixed) names, so no -f layering
# is needed here beyond the implicit compose.yaml in $STACK_DIR. pi-auth/
# pi-sessions are never referenced below -- they must never be removed.
echo "==> Removing non-persisted volumes..."
VOLUMES_JSON="$(docker compose config --format json 2>/dev/null)" || VOLUMES_JSON=""
if [ -n "$VOLUMES_JSON" ]; then
  PKG_BIN_VOL="$(jq -r '.volumes["pkg-bin"].name // empty' <<<"$VOLUMES_JSON")"
  NIX_STORE_VOL="$(jq -r '.volumes["nix-store"].name // empty' <<<"$VOLUMES_JSON")"
  PROXY_DOMAINS_VOL="$(jq -r '.volumes["proxy-domains"].name // empty' <<<"$VOLUMES_JSON")"

  if [ "$PERSIST_PKGS" != "1" ] && [ -n "$PKG_BIN_VOL" ]; then
    echo "    removing non-persisted volume: $PKG_BIN_VOL (pkg-bin -- pass --persist-pkgs to keep it)"
    docker volume rm "$PKG_BIN_VOL" >/dev/null 2>&1 || true
  fi
  if [ "$PERSIST_STORE" != "1" ] && [ -n "$NIX_STORE_VOL" ]; then
    echo "    removing non-persisted volume: $NIX_STORE_VOL (nix-store -- omit --no-persist-store to keep it)"
    docker volume rm "$NIX_STORE_VOL" >/dev/null 2>&1 || true
  fi
  if [ "$PERSIST_DOMAINS" != "1" ] && [ -n "$PROXY_DOMAINS_VOL" ]; then
    echo "    removing non-persisted volume: $PROXY_DOMAINS_VOL (proxy-domains -- pass --persist-domains to keep it)"
    docker volume rm "$PROXY_DOMAINS_VOL" >/dev/null 2>&1 || true
  fi
else
  echo "    WARNING: couldn't resolve volume names via 'docker compose config' -- skipping non-persisted volume cleanup." >&2
fi

# --- Backstop: unmount any merged-store overlay left on the host ----------
# Normally nix-store-mounter's own shutdown trap already removed it (the
# umount propagates to the host). This catches a killed/crashed mounter, and
# the old host-side overlay from the previous design. Paths must match
# start-agent.sh.
MERGED_DIR="${PI_SANDBOX__NIX_STORE_MERGED_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/pi-sandbox/nix-store-merged}"
OLD_OVERLAY_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pi-sandbox/nix-store-overlay"
# Same backstop for the workspace-mounter staging dir (compose.workspace.yaml /
# containers/workspace-mounter) -- normally unmounted by its own SIGTERM
# trap, this only catches a killed/crashed mounter. Path must match
# start-agent.sh.
WORKSPACE_MERGED_DIR="${PI_SANDBOX__WORKSPACE_MERGED_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/pi-sandbox/workspace-merged}"
for dir in "$MERGED_DIR" "$OLD_OVERLAY_DIR" "$WORKSPACE_MERGED_DIR"; do
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