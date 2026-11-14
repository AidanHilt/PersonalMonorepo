#!/usr/bin/env bash
# nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack-nono#stop -- <name>
#
# Phase 4b of PLAN.md: replaces the old container-era `stop-agent`. Stops
# an existing nono session as the `pi` user, using that run's own per-run
# XDG_STATE_HOME (see scripts/ps.sh / attach.sh for the same pattern).
#
# Also stops that run's approval helper, best-effort. There is no PID
# file for it (see start-agent.sh's "Detached mode": the supervisor keeps
# the helper's PID only as a local shell variable and already kills it
# itself, ~5s after `nono ps` stops reporting the session) -- this script
# does NOT invent new PID-file plumbing (out of scope: approval-helper's
# Go code is not touched here). Instead it uses the port recorded in
# approval-helper-info.json (written by start-agent.sh's supervisor for
# --detached runs only) to stop the helper immediately via `fuser`/`lsof`
# if either is available; if neither is, or the run wasn't detached (no
# info file), the helper is left for the supervisor's own ~5s teardown --
# `nono stop` below has already caused that teardown to start either way.
set -euo pipefail

print_help() {
  cat <<'EOF'
Usage: stop.sh [--help] <name>

Stops an existing nono session under /var/lib/pi/runs/<name>/ (`nono stop
<name>`, run as the `pi` user against that run's own XDG_STATE_HOME), and
makes a best-effort attempt to also stop that run's approval helper
immediately (see the header comment in this file for why it's
best-effort, not guaranteed).

Positional arguments:
  <name>   The run/session name (as passed to start-agent.sh --name, or
           "pi" if that run used the default).

Flags:
  --help, -h   Show this help and exit.

Environment variables:
  PERSONAL_MONOREPO_LOCATION   Path to the monorepo checkout (required).
  PI_STACK_NONO_BIN            Absolute store path for nono, set
                                automatically by flake.nix's apps.stop
                                wrapper. Falls back to 'command -v nono'
                                (with a warning) if run directly.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  print_help
  exit 0
fi

NAME="${1:?usage: stop.sh <name> (run stop.sh --help for details)}"

: "${PERSONAL_MONOREPO_LOCATION:?PERSONAL_MONOREPO_LOCATION must point at the monorepo checkout}"
# shellcheck source=lib-common.sh
# shellcheck disable=SC1091
source "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack-nono/scripts/lib-common.sh"

RUN_DIR="$(require_run_dir "$NAME")"
STATE_DIR="$RUN_DIR/nono-xdg-state"

NONO_BIN="$(resolve_stack_bin PI_STACK_NONO_BIN nono)"

echo "==> Stopping nono session '$NAME'..." >&2
sudo -u pi env XDG_STATE_HOME="$STATE_DIR" "$NONO_BIN" stop "$NAME"

# Best-effort immediate teardown of the approval helper -- see header
# comment. Only present for --detached runs; a missing info file (e.g. a
# foreground run, whose helper already dies with the launcher process) is
# not an error.
INFO_FILE="$RUN_DIR/approval-helper-info.json"
if sudo -u pi test -f "$INFO_FILE"; then
  PORT=""
  if command -v jq >/dev/null 2>&1; then
    PORT="$(sudo -u pi jq -r '.port // empty' "$INFO_FILE" 2>/dev/null || true)"
  fi
  if [ -n "$PORT" ]; then
    if command -v fuser >/dev/null 2>&1; then
      sudo -u pi fuser -k -n tcp "$PORT" >/dev/null 2>&1 || true
    elif command -v lsof >/dev/null 2>&1; then
      HELPER_PID="$(sudo -u pi lsof -ti "tcp:$PORT" 2>/dev/null || true)"
      if [ -n "$HELPER_PID" ]; then
        sudo -u pi kill "$HELPER_PID" 2>/dev/null || true
      fi
    else
      echo "warning: neither fuser nor lsof found -- cannot stop the approval helper on port $PORT immediately. It will exit on its own once the run's supervisor notices the session has stopped (within ~5s)." >&2
    fi
  else
    echo "warning: could not read a port from $INFO_FILE (jq missing, or the file is malformed) -- leaving the approval helper's own supervisor-driven teardown (~5s) to stop it." >&2
  fi
  sudo -u pi rm -f "$INFO_FILE"
fi

echo "==> Stopped '$NAME'." >&2
