#!/usr/bin/env bash
# nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack-nono#ps
#
# Phase 4b of PLAN.md: a `ps`-equivalent wrapper over nono's own session
# listing. Per-run nono state means there is no single `nono ps` that sees
# every run at once (each run gets its own nono XDG_STATE_HOME, a sibling
# of $RUNS_ROOT at /var/lib/pi/<name>-nono-xdg-state -- see
# lib-common.sh's nono_state_dir_for and IMPLEMENTERS.md's "Launcher and
# approval helper (Phase 4a)" section) -- this script loops over every run
# directory under /var/lib/pi/runs and runs `nono ps` against each run's
# own XDG_STATE_HOME, as the `pi` user (relying on the same
# NOPASSWD+SETENV sudo rule start-agent.sh uses), printing a combined,
# per-run-labelled table.
set -euo pipefail

print_help() {
  cat <<'EOF'
Usage: ps.sh [--help]

Lists nono sessions across every /var/lib/pi/runs/<name>/ run directory,
labelled by run name. Runs `nono ps` as the `pi` user once per run,
against that run's own XDG_STATE_HOME at
/var/lib/pi/<name>-nono-xdg-state (each run has its own -- nono has no
single cross-run session registry), skipping any run whose state
directory doesn't exist and printing a labelled error line (to stderr,
without aborting the rest of the listing) for any run whose `nono ps`
call itself fails.

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
for run_dir in "$RUNS_ROOT"/*/; do
  [ -d "$run_dir" ] || continue
  name="$(basename "$run_dir")"
  state_dir="$(nono_state_dir_for "$name")"

  # A run directory with no corresponding nono state dir at all (e.g. a
  # stale/partial run) has nothing to list -- skip it silently, same as
  # the "no active sessions" case below.
  [ -d "$state_dir" ] || continue

  err_file="$(mktemp)"
  output=""
  if output="$(sudo -u pi env XDG_STATE_HOME="$state_dir" "$NONO_BIN" ps 2>"$err_file")"; then
    [ -n "$output" ] || {
      rm -f "$err_file"
      continue
    }
    found_any=1
    echo "== run: $name =="
    echo "$output"
    echo
  else
    # `nono ps` failing outright (as opposed to succeeding with no
    # sessions) is surfaced, not silently swallowed -- a single
    # stale/broken run shouldn't break the whole listing, but it also
    # shouldn't look identical to "nothing running here".
    found_any=1
    echo "== run: $name == (nono ps failed: $(tr '\n' ' ' <"$err_file"))" >&2
  fi
  rm -f "$err_file"
done

if [ "$found_any" -eq 0 ]; then
  echo "No active nono sessions found under $RUNS_ROOT." >&2
fi
