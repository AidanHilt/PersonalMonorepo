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
# kubeconfig exists (default path below, or PI_SANDBOX__KUBECONFIG_PATH), we
# layer compose.kube.yaml on top to mount it read-only into the `pi`
# container. If it's missing, we warn and continue without k8s access
# rather than blocking the whole stack on it.
KUBECONFIG_PATH="${PI_SANDBOX__KUBECONFIG_PATH:-$HOME/.config/pi-sandbox/agent-kubeconfig.yaml}"
COMPOSE_FILES=(-f compose.yaml)

# --- Secrets: arbitrary-name injection, never decrypted here --------------
# This script performs NO secret retrieval/decryption of its own. It only
# accepts already-decrypted values via two channels and forwards them into
# the `pi` container as `-e NAME=VALUE` on `docker compose run`:
#   1. Repeatable `--secret NAME=VALUE` CLI flags.
#   2. Host env vars namespaced `PI_SANDBOX__SECRET__<NAME>` (prefix
#      stripped to get NAME).
# The namespace scan runs first, then `--secret` flags are appended after
# it, so a `--secret` flag always wins over a same-named namespaced env var
# (later `-e` wins when docker encounters a duplicate name).
SECRET_ENV_ARGS=()

# --- pkg-broker store backend: CLI flag alias for the env var below -------
# '--host-store' is a plain boolean alias for PI_SANDBOX__PKGBROKER_HOST_STORE=1,
# parsed here alongside '--secret' so both can be combined in one invocation.
# Either the flag or the env var being '1' is enough to opt in (OR semantics).
HOST_STORE_FLAG=0

while [ $# -gt 0 ]; do
  case "$1" in
    --host-store)
      HOST_STORE_FLAG=1
      shift
      ;;
    --secret)
      shift
      secret_arg="${1:?--secret requires a NAME=VALUE argument}"
      secret_name="${secret_arg%%=*}"
      if [ -z "$secret_name" ] || [ "$secret_arg" = "${secret_arg#*=}" ]; then
        echo "error: --secret requires a NAME=VALUE argument with a non-empty NAME (got: $secret_arg)" >&2
        exit 1
      fi
      SECRET_ENV_ARGS+=(-e "$secret_arg")
      shift
      ;;
    --secret=*)
      secret_arg="${1#--secret=}"
      secret_name="${secret_arg%%=*}"
      if [ -z "$secret_name" ] || [ "$secret_arg" = "${secret_arg#*=}" ]; then
        echo "error: --secret requires a NAME=VALUE argument with a non-empty NAME (got: $secret_arg)" >&2
        exit 1
      fi
      SECRET_ENV_ARGS+=(-e "$secret_arg")
      shift
      ;;
    *)
      echo "error: unrecognized argument: $1" >&2
      exit 1
      ;;
  esac
done

SECRET_NAMESPACE_ARGS=()
while IFS= read -r var_name; do
  [ -n "$var_name" ] || continue
  secret_name="${var_name#PI_SANDBOX__SECRET__}"
  SECRET_NAMESPACE_ARGS+=(-e "${secret_name}=${!var_name}")
done < <(compgen -v PI_SANDBOX__SECRET__ || true)

# Namespace-discovered values first, explicit --secret flags appended
# after, so flags take precedence on a NAME collision.
SECRET_ENV_ARGS=("${SECRET_NAMESPACE_ARGS[@]}" "${SECRET_ENV_ARGS[@]}")

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
    (or place a pre-generated one at $KUBECONFIG_PATH / set PI_SANDBOX__KUBECONFIG_PATH)
EOF
fi

# --- pkg-broker store backend: default isolated volume vs. host-shared ----
# Mirrors the kubeconfig block above: an opt-in override, layered onto
# COMPOSE_FILES, rather than something this script decides on its own.
# Set PI_SANDBOX__PKGBROKER_HOST_STORE=1 (or pass '--host-store') to swap
# pkg-broker's default, empty 'nix-store' docker volume for the host's real
# /nix/store + 
# nix-daemon socket (compose.pkgbroker-host-store.yaml -- see
# containers/pkg-broker/README.md for the trust-boundary tradeoff that
# override makes). Resolved again, below, once we know which backend is
# active, to decide what pi's own /nix/store bind mount should point at.
if [ "$HOST_STORE_FLAG" = "1" ] || [ "${PI_SANDBOX__PKGBROKER_HOST_STORE:-0}" = "1" ]; then
  PKGBROKER_HOST_STORE=1
else
  PKGBROKER_HOST_STORE=0
fi
echo "==> Checking pkg-broker store backend..."
if [ "$PKGBROKER_HOST_STORE" = "1" ]; then
  echo "    PI_SANDBOX__PKGBROKER_HOST_STORE=1 / --host-store — layering compose.pkgbroker-host-store.yaml (pkg-broker shares the host's real nix store/daemon)."
  COMPOSE_FILES+=(-f compose.pkgbroker-host-store.yaml)
else
  echo "    Using pkg-broker's default, isolated 'nix-store' volume (set PI_SANDBOX__PKGBROKER_HOST_STORE=1 or pass --host-store to share the host's real store instead)."
  COMPOSE_FILES+=(-f compose.nixstore-overlay.yaml)
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

echo "==> Building and loading pi/proxy/pkg-broker images into the active Docker context..."
DOCKER_CTX="$(docker context show 2>/dev/null || echo 'default')"
echo "    Active Docker context: $DOCKER_CTX"

override_flag=()
if [ -n "${PERSONAL_MONOREPO_LOCATION:-}" ] && [ -d "$PERSONAL_MONOREPO_LOCATION/nix/scripts" ]; then
  override_flag=(--override-input scripts "path:$PERSONAL_MONOREPO_LOCATION/nix/scripts")
  echo "==> Using local nix/scripts checkout at $PERSONAL_MONOREPO_LOCATION/nix/scripts"
fi

nix run "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#load" "${override_flag[@]}"

# --- pi's /nix/store source -------------------------------------------------
# - Host-store mode: pkg-broker shares the host's real /nix, and `nix run
#   .#load` already realized pi's closure there, so pi just binds the host's
#   /nix/store read-only.
# - Default mode: pi's /nix/store is the union of pi's OWN image store and the
#   shared nix-store volume (what pkg-broker builds). That union is built by
#   the nix-store-mounter service (compose.nixstore-overlay.yaml), which runs
#   the pi image with CAP_SYS_ADMIN and publishes the overlay to a host
#   directory via mount propagation; pi binds that directory (rslave). No
#   host-side overlay, no `sudo mount`, no reaching into docker volume dirs,
#   and pkg-broker never sees pi's closure.
UP_SERVICES=(proxy pkg-broker)
if [ "$PKGBROKER_HOST_STORE" = "1" ]; then
  echo "==> pkg-broker host-store override is active -- pi will bind the host's real /nix/store directly."
  export PI_SANDBOX__NIX_STORE_SOURCE="/nix/store"
else
  NIX_STORE_MERGED_DIR="${PI_SANDBOX__NIX_STORE_MERGED_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/pi-sandbox/nix-store-merged}"
  echo "==> Preparing merged /nix/store directory $NIX_STORE_MERGED_DIR (populated by nix-store-mounter)..."
  mkdir -p "$NIX_STORE_MERGED_DIR"

  # A leftover overlay (crashed mounter) would be stacked under the new one
  # and hold stale lower layers, so clear it first.
  while mountpoint -q "$NIX_STORE_MERGED_DIR"; do
    echo "    stale mount found at $NIX_STORE_MERGED_DIR -- unmounting (sudo)."
    sudo umount "$NIX_STORE_MERGED_DIR"
  done

  # Docker only accepts rshared/rslave binds from a shared (or slave) mount.
  prop="$(findmnt -n -o PROPAGATION -T "$NIX_STORE_MERGED_DIR" 2>/dev/null || true)"
  case "$prop" in
    *shared*|*slave*) ;;
    *) echo "    WARNING: $NIX_STORE_MERGED_DIR is on a mount with propagation '${prop:-unknown}', not shared." >&2
       echo "    The overlay will not be visible to pi. Fix with: sudo mount --make-rshared /" >&2 ;;
  esac

  export PI_SANDBOX__NIX_STORE_SOURCE="$NIX_STORE_MERGED_DIR"
  UP_SERVICES+=(nix-store-mounter)
fi

echo "==> Starting docker compose stack (pi + proxy + pkg-broker${NIX_STORE_MERGED_DIR:+ + nix-store-mounter})..."
docker compose "${COMPOSE_FILES[@]}" up -d --wait "${UP_SERVICES[@]}"

cleanup() {
echo "==> Session finished — tearing down the compose stack..."
docker compose "${COMPOSE_FILES[@]}" down --remove-orphans
if [ -n "${NIX_STORE_MERGED_DIR:-}" ]; then
  # nix-store-mounter unmounts on SIGTERM; this only catches a killed one.
  while mountpoint -q "$NIX_STORE_MERGED_DIR" 2>/dev/null; do
    sudo umount "$NIX_STORE_MERGED_DIR" || break
  done
fi
}
trap cleanup EXIT

docker compose "${COMPOSE_FILES[@]}" run --rm "${SECRET_ENV_ARGS[@]}" pi