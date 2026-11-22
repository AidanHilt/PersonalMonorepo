#!/usr/bin/env bash
# nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#attach [-- <name>]
#
# Attaches to an existing nono session as the `pi` user, against the
# single shared nono XDG_STATE_HOME (see lib-common.sh's nono_state_dir
# and IMPLEMENTERS.md's "Single nono state dir" section -- there is no
# cross-run session registry beyond `nono ps` itself, see scripts/ps.sh).
#
# <name> is optional: when exactly one MAIN session (i.e. not a
# "<name>-shell") is live, it's auto-selected -- pass a name explicitly
# when zero or several are live. Deliberately does NOT require a
# /tmp/pi-sessions/<name> bookkeeping directory to exist: that directory
# is transient scratch (see SESSIONS_ROOT), and a live session must stay
# attachable even if it's been cleaned up by the OS.
set -euo pipefail

print_help() {
  cat <<'EOF'
Usage: attach.sh [--help] [<name>]

Attaches to an existing nono session (`nono attach <name>`, run as the
`pi` user against the single shared nono XDG_STATE_HOME).

Positional arguments:
  <name>   The run/session name (as passed to start-agent.sh --name, or
           "pi" if that run used the default). Optional: if omitted and
           exactly one MAIN session is currently live, that one is used
           automatically; otherwise this errors, listing the live
           sessions (or lack thereof).

Flags:
  --help, -h   Show this help and exit.

Environment variables:
  PERSONAL_MONOREPO_LOCATION   Path to the monorepo checkout (required).
  PI_STACK_NONO_BIN            Absolute store path for nono, set
                                automatically by flake.nix's apps.attach
                                wrapper. Falls back to 'command -v nono'
                                (with a warning) if run directly.
  PI_STACK_NONO_STATE_ROOT     Overrides the shared nono state root (see
                                lib-common.sh's nono_state_dir).
EOF
}

NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
  --help | -h)
    print_help
    exit 0
    ;;
  -*)
    echo "error: unrecognized argument: $1" >&2
    exit 1
    ;;
  *)
    if [ -n "$NAME" ]; then
      echo "error: unexpected extra argument: $1 (name already given: $NAME)" >&2
      exit 1
    fi
    NAME="$1"
    shift
    ;;
  esac
done

: "${PERSONAL_MONOREPO_LOCATION:?PERSONAL_MONOREPO_LOCATION must point at the monorepo checkout}"
# shellcheck source=lib-common.sh
# shellcheck disable=SC1091
source "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack/scripts/lib-common.sh"

NONO_BIN="$(resolve_stack_bin PI_STACK_NONO_BIN nono)"
STATE_DIR="$(nono_state_dir)"

NAME="$(resolve_name_or_auto "$NAME" "$NONO_BIN" "$STATE_DIR")"

exec sudo -u pi env XDG_STATE_HOME="$STATE_DIR" "$NONO_BIN" attach "$NAME"
