#!/usr/bin/env bash
# Entrypoint for the `pi` service container.
#
# Responsibilities (deliberately small — this is not where the security
# boundary lives, that's the container/network config in compose.yaml):
#   1. Sanity-check that the expected mounts are present.
#   2. Fall back to a default AGENTS.md if the project doesn't ship one.
#   3. Exec `pi` as PID 1 so it receives signals directly (no orphaned
#      node process on `docker compose down`).
set -euo pipefail

PROJECT_DIR="${PERSONAL_MONOREPO_LOCATION:-/workspace}"
AGENT_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}"

if [ ! -d "$PROJECT_DIR" ] || [ -z "$(ls -A "$PROJECT_DIR" 2>/dev/null)" ]; then
  echo "warning: $PROJECT_DIR is empty or missing — check the project bind mount in compose.yaml" >&2
fi

if [ ! -f "$PROJECT_DIR/AGENTS.md" ] && [ ! -f "$PROJECT_DIR/AGENTS.override.md" ]; then
  echo "info: no AGENTS.md in project root, using bundled default from $AGENT_DIR/defaults/AGENTS.md" >&2
  cp "$AGENT_DIR/defaults/AGENTS.md" "$PROJECT_DIR/AGENTS.md" ||
    echo "warning: could not write default AGENTS.md (read-only project mount?) — continuing without one" >&2
fi

if [ -f /home/pi/.kube/config ]; then
  export KUBECONFIG=/home/pi/.kube/config
else
  unset KUBECONFIG
fi

# The auth directory (bind-mounted read-write at /mnt/auth-store, see
# spec §7) holds ~/.pi/agent/auth.json as written by the `login`
# profile. It's mounted outside ~/.pi/agent so it doesn't shadow the
# baked-in settings.json/models.json/permission config — symlink the
# actual file in instead of mounting the directory over ~/.pi/agent.
AUTH_STORE=/mnt/auth-store
if [ -d "$AUTH_STORE" ]; then
  mkdir -p "$AUTH_STORE"
  touch "$AUTH_STORE/auth.json"
  ln -sf "$AUTH_STORE/auth.json" "$AGENT_DIR/auth.json"
else
  echo "info: no auth-store mount found; relying on env-var API keys for this run" >&2
fi

cd "$PROJECT_DIR"

# `pi` binary lives in the pinned npm deps' .bin, already on PATH via
# the image's Env. `--no-session` keeps runs stateless by default per
# spec §3.1 (flip this by mounting a session volume and dropping the
# flag, if persistence across runs is ever wanted).
exec pi --no-session "$@"
