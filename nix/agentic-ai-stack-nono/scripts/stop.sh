#!/usr/bin/env bash
# nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack-nono#stop -- <name>
#
# Phase 4b of PLAN.md: replaces the old container-era `stop-agent`. Stops
# an existing nono session as the `pi` user, using that run's own per-run
# XDG_STATE_HOME at /var/lib/pi/<name>-nono-xdg-state (see
# lib-common.sh's nono_state_dir_for; scripts/ps.sh / attach.sh use the
# same path).
#
# The approval helper's own lifecycle is NOT this script's job: for a
# foreground run, start-agent.sh's own launcher process owns it (it dies
# with the launcher). For a detached run, the invoking-user wrapper
# started by start-agent.sh owns it, and stops it itself once the
# pi-owned supervisor it's waiting on (which polls `nono ps` every 5s)
# returns -- `nono stop` below causes that supervisor to notice and return
# on its own, so the helper gets stopped either way, just not necessarily
# instantly. There is deliberately no PID-file plumbing added here to
# make that teardown immediate (out of scope: approval-helper's Go code
# is not touched here).
#
# After a successful `nono stop`, this script also releases every
# live-shared path recorded for this run (lib-common.sh's
# share_release, the counterpart of start-agent.sh's share_grant --
# ownership of anything `pi` left behind is normalized back to the
# invoking user, then the ACL entries share_grant added are removed),
# then deletes the per-run nono state directory's contents -- EXCEPT its
# nono/audit subtree, which is preserved (nono stores audit records at
# <XDG_STATE_HOME>/nono/audit). If `nono stop` fails, nothing is deleted
# or released.
#
# Refuses outright (before stopping, releasing, or deleting anything) if
# a "<name>-shell" session (scripts/shell.sh, `nix run .#shell --
# <name>`) is still open for this run -- shell.sh reuses this run's own
# XDG_STATE_HOME, so tearing it down here out from under an open shell
# would be surprising. See lib-common.sh's nono_session_running.
set -euo pipefail

print_help() {
  cat <<'EOF'
Usage: stop.sh [--help] <name>

Stops an existing nono session under /var/lib/pi/runs/<name>/ (`nono stop
<name>`, run as the `pi` user against that run's own XDG_STATE_HOME at
/var/lib/pi/<name>-nono-xdg-state). On success, releases every
live-shared path recorded for this run (its workdir and every
--add/--clone extra -- ownership of anything `pi` left behind is
normalized back to you, via an interactive `sudo` prompt, and the ACL
entries removed, unless another still-live run also shares that same
path), then deletes that state directory's contents, preserving its
nono/audit subtree. The approval helper's own lifecycle is NOT managed
by this script -- see the header comment in this file for who owns it.

Run this after a crashed/interrupted start-agent.sh launch too -- it's
the way to finish restoring ownership/ACLs on whatever was live-shared
if the launcher's own teardown (its EXIT trap, or the detached wrapper)
never got to run.

Refuses outright (stopping/releasing/deleting nothing) if a
"<name>-shell" session (`nix run .#shell -- <name>`) is still open for
this run -- exit that shell first, then re-run stop.sh.

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

# require_run_dir validates $NAME and that its run directory exists;
# its own output (the run dir path) is needed below for the live
# file-sharing release step (RUN_DIR/shared-paths) -- the nono state dir
# itself still lives OUTSIDE it, as a sibling of $RUNS_ROOT (see
# nono_state_dir_for).
RUN_DIR="$(require_run_dir "$NAME")"
STATE_DIR="$(nono_state_dir_for "$NAME")"

NONO_BIN="$(resolve_stack_bin PI_STACK_NONO_BIN nono)"

# Refuse before touching anything if this run's shell session
# (scripts/shell.sh, `nix run .#shell -- <name>`) is still open -- it
# shares this run's own XDG_STATE_HOME, so stopping/deleting state here
# out from under it would be surprising.
SHELL_SESSION_NAME="${NAME}-shell"
if nono_session_running "$NONO_BIN" "$STATE_DIR" "$SHELL_SESSION_NAME"; then
  echo "error: a shell session ($SHELL_SESSION_NAME) is still open for run $NAME; exit it first" >&2
  exit 1
fi

echo "==> Stopping nono session '$NAME'..." >&2
if ! sudo -u pi env XDG_STATE_HOME="$STATE_DIR" "$NONO_BIN" stop "$NAME"; then
  echo "error: 'nono stop $NAME' failed -- leaving $STATE_DIR untouched (not deleting anything)." >&2
  exit 1
fi

# Release every live-shared path recorded for this run (its workdir and
# every --add/--clone extra, lib-common.sh's share_grant counterpart) --
# ownership of anything `pi` left behind is normalized back to the
# invoking user and the ACL entries share_grant added are removed,
# unless some OTHER still-live run also shares that same path.
# Interactive sudo is fine here (this script is meant to be run
# attended). Idempotent: running `stop` again after a path has already
# been released is a no-op for that path.
while IFS= read -r shared_path; do
  [ -n "$shared_path" ] || continue
  share_release "$shared_path" --self-run "$NAME" || echo "warning: failed to release live share of $shared_path -- restoring ownership/ACLs for it may need to be finished by hand." >&2
done < <(share_read_paths "$RUN_DIR")

# Clean up the per-run nono state dir now that the session is confirmed
# stopped, preserving nono/audit (and the audit record subtree) --
# everything else under $STATE_DIR is disposable per-session scratch
# state. If the state dir has no audit subtree at all, it's removed
# outright instead of leaving an empty shell behind.
if sudo -u pi test -d "$STATE_DIR"; then
  if sudo -u pi test -d "$STATE_DIR/nono/audit"; then
    echo "==> Removing $STATE_DIR contents (preserving nono/audit)..." >&2
    # Delete everything directly under $STATE_DIR except the `nono`
    # directory itself (which holds audit/), then, within `nono/`,
    # delete everything except `audit` -- the net effect is: keep only
    # $STATE_DIR/nono/audit, delete everything else.
    sudo -u pi find "$STATE_DIR" -mindepth 1 -maxdepth 1 ! -name nono -exec rm -rf -- {} +
    sudo -u pi find "$STATE_DIR/nono" -mindepth 1 -maxdepth 1 ! -name audit -exec rm -rf -- {} +
    echo "    kept: $STATE_DIR/nono/audit" >&2
  else
    echo "==> Removing $STATE_DIR (no nono/audit subtree to preserve)..." >&2
    sudo -u pi rm -rf -- "$STATE_DIR"
  fi
fi

echo "==> Stopped '$NAME'." >&2
