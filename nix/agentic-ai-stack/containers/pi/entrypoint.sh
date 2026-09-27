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

# Stage the immutable, baked agent config into the writable ~/.pi tmpfs.
# Everything under ~/.pi is ephemeral by design; the source of truth is
# the .pi-seed baked into the image (settings.json, models.json,
# extensions, permission-system policy, default AGENTS.md). auth.json and
# the sessions dir are bind-mounted on top of the tmpfs and are NOT part
# of the seed, so this copy leaves them untouched.
mkdir -p "$HOME/.pi"
cp -a /home/pi/.pi-seed/* "$HOME/.pi/"

PROJECT_DIR="${PERSONAL_MONOREPO_LOCATION:-/workspace}"
#AGENT_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}"

if [ ! -d "$PROJECT_DIR" ] || [ -z "$(ls -A "$PROJECT_DIR" 2>/dev/null)" ]; then
  echo "warning: $PROJECT_DIR is empty or missing — check the project bind mount in compose.yaml" >&2
fi

if [ -f /home/pi/.kube/config ]; then
  export KUBECONFIG=/home/pi/.kube/config
else
  unset KUBECONFIG
fi

# auth.json is bind-mounted directly at ~/.pi/agent/auth.json (see
# compose.yaml), written by the `login` flow on the host and persisted
# there. No symlink/auth-store juggling needed anymore.

cd "$PROJECT_DIR" || exit

# `pi` binary lives in the pinned npm deps' .bin, already on PATH via
# the image's Env. `--no-session` keeps runs stateless by default per
# spec §3.1 (flip this by mounting a session volume and dropping the
# flag, if persistence across runs is ever wanted).
exec pi --no-session "$@"
