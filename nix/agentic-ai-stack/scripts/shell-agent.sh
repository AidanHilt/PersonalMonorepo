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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$REPO_ROOT"

# `docker compose run --rm pi` (what start-agent.sh uses) creates a
# service container that doesn't reliably show up under plain
# `docker compose ps` across Compose versions (it's a one-off run
# container, not a long-lived `up -d` service) -- so rather than parsing
# `ps` output, just try the thing we actually care about: can we exec
# into it right now.
if ! docker compose exec -T pi true >/dev/null 2>&1; then
  cat >&2 <<'EOF'
error: the `pi` service container is not currently running (or is not
reachable via `docker compose exec`).

Start it first:
  nix run .#start-agent

...then re-run `nix run .#shell-agent` from another terminal.
EOF
  exit 1
fi

echo "==> Shelling into the running pi container..."
exec docker compose exec pi bash
