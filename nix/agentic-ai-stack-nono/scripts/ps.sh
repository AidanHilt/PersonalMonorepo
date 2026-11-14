#!/usr/bin/env bash
# nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack-nono#ps
#
# Phase 4b of PLAN.md: a `ps`-equivalent wrapper over nono's own session
# listing. Per-run nono state means there is no single `nono ps` that sees
# every run at once (each run gets its own nono-xdg-state directory, see
# IMPLEMENTERS.md's "Launcher and approval helper (Phase 4a)" section) --
# this script loops over every run under /var/lib/pi/runs and runs `nono
# ps` against each run's own XDG_STATE_HOME, as the `pi` user (relying on
# the same NOPASSWD+SETENV sudo rule start-agent.sh uses), printing a
# combined, per-run-labelled table.
set -euo pipefail

print_help() {
  cat <<'EOF'
Usage: ps.sh [--help]

Lists nono sessions across every /var/lib/pi/runs/<name>/ run directory,
labelled by run name. Runs `nono ps` as the `pi` user once per run (each
run has its own XDG_STATE_HOME -- nono has no single cross-run session
registry), skipping any run with no active sessions.

Flags:
  --help, -h   Show this help and exit.

Environment variables:
  PERSONAL_MONOREPO_LOCATION   Path to the monorepo checkout (required).
  PI_STACK_NONO_BIN            Absolute store path for nono, set
                                automatically by flake.nix's apps.ps
                                wrapper. Falls back to 'command -v nono'
                                (with a warning) if run directly.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  print_help
  exit 0
fi

: "${PERSONAL_MONOREPO_LOCATION:?PERSONAL_MONOREPO_LOCATION must point at the monorepo checkout}"
# shellcheck source=lib-common.sh
# shellcheck disable=SC1091
source "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack-nono/scripts/lib-common.sh"

NONO_BIN="$(resolve_stack_bin PI_STACK_NONO_BIN nono)"

shopt -s nullglob
found_any=0
for state_dir in "$RUNS_ROOT"/*/nono-xdg-state; do
  [ -d "$state_dir" ] || continue
  run_dir="$(dirname "$state_dir")"
  name="$(basename "$run_dir")"

  output=""
  if output="$(sudo -u pi env XDG_STATE_HOME="$state_dir" "$NONO_BIN" ps 2>/dev/null)"; then
    :
  else
    # `nono ps` against a run with no sessions (or a transient error) --
    # skip it rather than fail the whole listing.
    continue
  fi
  [ -n "$output" ] || continue

  found_any=1
  echo "== run: $name =="
  echo "$output"
  echo
done

if [ "$found_any" -eq 0 ]; then
  echo "No active nono sessions found under $RUNS_ROOT." >&2
fi
