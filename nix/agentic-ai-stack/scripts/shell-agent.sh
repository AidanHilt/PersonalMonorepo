#!/usr/bin/env bash
# nix run .#shell-agent
#
# Convenience wrapper that execs an interactive shell into the already-
# running default-profile `pi` service container -- for manually
# exercising/debugging things like `pkg-install`/`pkg-broker` without
# having to discover the running container name/ID by hand. This is a
# raw shell, unrestricted by Pi's own app-level permission system (it
# bypasses the agent harness entirely), but still bound by the same
# internal-network/no-external-route sandboxing as any other `pi`
# session (spec: the actual security boundary is the container/network
# config, not Pi's own prompts).
#
# Deliberately does NOT start the stack itself if `pi` isn't already
# running -- start it first with `nix run .#start-agent`.
set -euo pipefail

# Find the container by the labels Compose puts on it, using plain `docker`
# instead of `docker compose`. Why:
#   - `docker compose exec` only reliably sees containers started by `up`,
#     but start-agent.sh starts pi with `docker compose run`, which creates
#     a one-off container (agentic-ai-stack-pi-run-<id>).
#   - Every `docker compose` command has to parse compose.yaml, which needs
#     PI_SANDBOX__NIX_STORE_SOURCE set and the working directory to be the
#     stack directory. Under `nix run` this script lives in the Nix store,
#     so neither can be assumed.
# Label lookup needs none of that. The project name defaults to the stack
# directory's name; override with COMPOSE_PROJECT_NAME if you changed it.
PROJECT="${COMPOSE_PROJECT_NAME:-agentic-ai-stack}"

# Newest first; take the first match. Matches both `run` (oneoff=True) and
# `up` (oneoff=False) containers of the `pi` service. The `login` service
# has its own service label, so it never matches.
CONTAINER_ID="$(docker ps -q \
  --filter "label=com.docker.compose.project=${PROJECT}" \
  --filter "label=com.docker.compose.service=pi" \
  | head -n1)"

if [ -z "$CONTAINER_ID" ]; then
  cat >&2 <<EOF
error: no running \`pi\` container found for compose project '${PROJECT}'.

Start it first:
  nix run .#start-agent

...then re-run \`nix run .#shell-agent\` from another terminal.
(If you changed the compose project name, set COMPOSE_PROJECT_NAME.)
EOF
  exit 1
fi

echo "==> Shelling into the running pi container ($(docker inspect --format '{{.Name}}' "$CONTAINER_ID" | sed 's|^/||'))..."
exec docker exec -it "$CONTAINER_ID" bash