#!/usr/bin/env bash
# Entrypoint for the `pi` and `login` service containers (same image,
# different invocation — see compose.yaml).
#
# Responsibilities (deliberately small — this is not where the security
# boundary lives, that's the container/network config in compose.yaml):
#   1. Stage the immutable seed into the writable ~/.pi tmpfs and symlink
#      the persistent auth/session state on top of it.
#   2. Sanity-check that the expected mounts are present.
#   3. Exec `pi` as PID 1 so it receives signals directly (no orphaned
#      node process on `docker compose down`).
set -euo pipefail

# Stage the immutable, baked agent config into the writable ~/.pi tmpfs.
# Everything under ~/.pi is ephemeral by design; the source of truth is
# the .pi-seed baked into the image (settings.json, models.json,
# extensions, permission-system policy, default AGENTS.md).
mkdir -p "$HOME/.pi"
cp -a /home/pi/.pi-seed/* "$HOME/.pi/"

# auth.json and the sessions dir are the two genuinely mutable,
# host-persisted items (spec §7). They live on named Docker volumes
# mounted at /home/pi/.pi-state/{auth,sessions} (see compose.yaml), not
# inside the seed. Replace whatever the seed copy put at their paths
# (normally nothing — the seed doesn't ship either) with symlinks into
# the persistent volumes, so both the `pi` and `login` invocations below
# read/write the same durable state regardless of which one runs.
mkdir -p /home/pi/.pi-state/auth /home/pi/.pi-state/sessions
touch /home/pi/.pi-state/auth/auth.json

rm -rf "$HOME/.pi/agent/auth.json"
ln -s /home/pi/.pi-state/auth/auth.json "$HOME/.pi/agent/auth.json"

rm -rf "$HOME/.pi/agent/sessions"
ln -s /home/pi/.pi-state/sessions "$HOME/.pi/agent/sessions"

if [ -f /home/pi/.kube/config ]; then
  export KUBECONFIG=/home/pi/.kube/config
else
  unset KUBECONFIG
fi

# Login mode: invoked as `login` (see compose.yaml's `login` service
# `command: ["login"]`). This is the interactive OAuth flow — it ignores
# PI_SESSIONS/--no-session entirely and just runs `pi` natively so it can
# drive its own login UI. Only the seed-copy/symlink setup above is
# shared with the normal run mode below.
if [ "${1:-}" = "login" ]; then
  shift
  exec pi "$@"
fi

PROJECT_DIR="${PERSONAL_MONOREPO_LOCATION:-/workspace}"
#AGENT_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}"

if [ "${PI_LOGIN_FORWARD:-0}" != "1" ] && { [ ! -d "$PROJECT_DIR" ] || [ -z "$(ls -A "$PROJECT_DIR" 2>/dev/null)" ]; }; then
  echo "warning: $PROJECT_DIR is empty or missing — check the project bind mount in compose.yaml" >&2
fi

cd "$PROJECT_DIR" || exit

# `pi` binary lives in the pinned npm deps' .bin, already on PATH via
# the image's Env. Sessions are ON by default now (persisted via the
# pi-sessions volume, see compose.yaml) — set PI_SESSIONS=0 to run
# stateless (adds --no-session back) if persistence isn't wanted for a
# given run.
PI_ARGS=()
if [ "${PI_SESSIONS:-1}" = "0" ]; then
  PI_ARGS+=("--no-session")
fi

if [ "${PI_LOGIN_FORWARD:-0}" = "1" ]; then
      socat "TCP-LISTEN:${PI_FORWARD_LISTEN:-53693},bind=0.0.0.0,fork,reuseaddr" \
        "TCP:127.0.0.1:${PI_FORWARD_TARGET:-53692}" &
fi

exec "$@"

exec pi "${PI_ARGS[@]}" "$@"
