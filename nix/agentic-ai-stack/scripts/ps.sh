#!/usr/bin/env bash
# nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#ps
#
# A `ps`-equivalent wrapper over nono's own session listing. Every session
# in this stack (every start-agent.sh run, and every shell.sh "<name>-shell")
# now shares ONE nono XDG_STATE_HOME (see lib-common.sh's nono_state_dir),
# so this is just a single `nono ps` call against it, run as the `pi`
# user -- no more looping over per-run state directories.
set -euo pipefail

print_help() {
  cat <<'EOF'
Usage: ps.sh [--help]

Lists every live nono session (run as the `pi` user against the single
shared nono XDG_STATE_HOME -- see IMPLEMENTERS.md's "Single nono state
dir" section).

Flags:
  --help, -h   Show this help and exit.

Environment variables:
  PERSONAL_MONOREPO_LOCATION   Path to the monorepo checkout (required).
  PI_STACK_NONO_BIN            Absolute store path for nono, set
                                automatically by flake.nix's apps.ps
                                wrapper. Falls back to 'command -v nono'
                                (with a warning) if run directly.
  PI_STACK_NONO_STATE_ROOT     Overrides the shared nono state root (see
                                lib-common.sh's nono_state_dir).
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  print_help
  exit 0
fi

: "${PERSONAL_MONOREPO_LOCATION:?PERSONAL_MONOREPO_LOCATION must point at the monorepo checkout}"
# shellcheck source=lib-common.sh
# shellcheck disable=SC1091
source "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack/scripts/lib-common.sh"

NONO_BIN="$(resolve_stack_bin PI_STACK_NONO_BIN nono)"
STATE_DIR="$(nono_state_dir)"

if [ ! -d "$STATE_DIR" ]; then
  echo "No active nono sessions found (state dir $STATE_DIR does not exist yet)." >&2
  exit 0
fi

exec sudo -u pi env XDG_STATE_HOME="$STATE_DIR" "$NONO_BIN" ps
