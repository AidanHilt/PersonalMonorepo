#!/usr/bin/env bash
# nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack-nono#attach -- <name>
#
# Phase 4b of PLAN.md: replaces the old container-era `shell-agent`.
# Attaches to an existing nono session as the `pi` user, using that run's
# own per-run XDG_STATE_HOME (see IMPLEMENTERS.md's "Per-run state layout"
# -- there is no cross-run session registry, see scripts/ps.sh).
set -euo pipefail

print_help() {
  cat <<'EOF'
Usage: attach.sh [--help] <name>

Attaches to an existing nono session under /var/lib/pi/runs/<name>/
(`nono attach <name>`, run as the `pi` user against that run's own
XDG_STATE_HOME).

Positional arguments:
  <name>   The run/session name (as passed to start-agent.sh --name, or
           "pi" if that run used the default).

Flags:
  --help, -h   Show this help and exit.

Environment variables:
  PERSONAL_MONOREPO_LOCATION   Path to the monorepo checkout (required).
  PI_STACK_NONO_BIN            Absolute store path for nono, set
                                automatically by flake.nix's apps.attach
                                wrapper. Falls back to 'command -v nono'
                                (with a warning) if run directly.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  print_help
  exit 0
fi

NAME="${1:?usage: attach.sh <name> (run attach.sh --help for details)}"

: "${PERSONAL_MONOREPO_LOCATION:?PERSONAL_MONOREPO_LOCATION must point at the monorepo checkout}"
# shellcheck source=lib-common.sh
# shellcheck disable=SC1091
source "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack-nono/scripts/lib-common.sh"

RUN_DIR="$(require_run_dir "$NAME")"
STATE_DIR="$RUN_DIR/nono-xdg-state"

NONO_BIN="$(resolve_stack_bin PI_STACK_NONO_BIN nono)"

exec sudo -u pi env XDG_STATE_HOME="$STATE_DIR" "$NONO_BIN" attach "$NAME"
