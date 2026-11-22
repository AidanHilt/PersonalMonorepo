#!/usr/bin/env bash
# nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#stop [-- <name>]
#
# Stops an existing nono session as the `pi` user, against the single
# shared nono XDG_STATE_HOME every session in this stack uses (see
# lib-common.sh's nono_state_dir; scripts/ps.sh/attach.sh/shell.sh use the
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
# live-shared path recorded for this run (lib-common.sh's share_release,
# the counterpart of start-agent.sh's share_grant -- ownership of
# anything `pi` left behind is normalized back to the invoking user, then
# the ACL entries share_grant added are removed), then -- ONLY if no
# other session is live anywhere -- wipes the shared nono state
# directory's contents, EXCEPT its nono/audit subtree (preserved; nono
# stores audit records at <XDG_STATE_HOME>/nono/audit). If `nono stop`
# fails, nothing is deleted or released. Since the state dir is now
# shared by every session (see "Single nono state dir" in
# IMPLEMENTERS.md), a still-live sibling session blocks the wipe (but
# never blocks the stop/release of THIS run).
#
# Refuses outright (before stopping, releasing, or deleting anything) if
# a "<name>-shell" session (scripts/shell.sh, `nix run .#shell --
# <name>`) is still open for this run -- shell.sh reuses this run's own
# XDG_STATE_HOME, so tearing it down here out from under an open shell
# would be surprising. See lib-common.sh's nono_session_running.
set -euo pipefail

print_help() {
  cat <<'EOF'
Usage: stop.sh [--help] [<name>]

Stops an existing nono session (`nono stop <name>`, run as the `pi` user
against the single shared nono XDG_STATE_HOME). On success, releases
every live-shared path recorded for this run (its workdir and every
--add/--clone extra -- ownership of anything `pi` left behind is
normalized back to you, via an interactive `sudo` prompt, and the ACL
entries removed, unless another still-live run also shares that same
path), then -- only if no other session is live anywhere -- wipes the
shared nono state directory's contents, preserving its nono/audit
subtree. The approval helper's own lifecycle is NOT managed by this
script -- see the header comment in this file for who owns it.

Run this after a crashed/interrupted start-agent.sh launch too -- it's
the way to finish restoring ownership/ACLs on whatever was live-shared
if the launcher's own teardown (its EXIT trap, or the detached wrapper)
never got to run.

Refuses outright (stopping/releasing/deleting nothing) if a
"<name>-shell" session (`nix run .#shell -- <name>`) is still open for
this run -- exit that shell first, then re-run stop.sh.

Positional arguments:
  <name>   The run/session name (as passed to start-agent.sh --name, or
           "pi" if that run used the default). Optional: if omitted,
           this looks at both (a) live MAIN sessions and (b) leftover
           /tmp/pi-sessions/<name> bookkeeping directories with no live
           session at all (e.g. a crashed launch) -- if exactly one
           candidate exists across both, it's used automatically;
           otherwise this errors, listing every candidate found.

Flags:
  --help, -h   Show this help and exit.

Environment variables:
  PERSONAL_MONOREPO_LOCATION   Path to the monorepo checkout (required).
  PI_STACK_NONO_BIN            Absolute store path for nono, set
                                automatically by flake.nix's apps.stop
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

NAME="${1:-}"
if [ -n "${2:-}" ]; then
  echo "error: unexpected extra argument: $2 (name already given: $NAME)" >&2
  exit 1
fi

: "${PERSONAL_MONOREPO_LOCATION:?PERSONAL_MONOREPO_LOCATION must point at the monorepo checkout}"
# shellcheck source=lib-common.sh
# shellcheck disable=SC1091
source "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack/scripts/lib-common.sh"

NONO_BIN="$(resolve_stack_bin PI_STACK_NONO_BIN nono)"
STATE_DIR="$(nono_state_dir)"

if [ -z "$NAME" ]; then
  # No name given: build the combined candidate list -- live MAIN
  # sessions, PLUS leftover $SESSIONS_ROOT/<name> bookkeeping dirs that
  # have no live session at all (main or shell) -- the recovery path for
  # a crashed/interrupted launch whose own teardown never ran. Exactly
  # one candidate overall -> use it; otherwise error, listing every
  # candidate.
  CANDIDATES=()
  while IFS= read -r live_name; do
    [ -n "$live_name" ] || continue
    CANDIDATES+=("$live_name")
  done < <(nono_list_live_main_sessions "$NONO_BIN" "$STATE_DIR")

  shopt -s nullglob
  for leftover_dir in "$SESSIONS_ROOT"/*/; do
    [ -d "$leftover_dir" ] || continue
    leftover_name="$(basename "$leftover_dir")"
    already_counted=0
    for c in "${CANDIDATES[@]:-}"; do
      [ "$c" = "$leftover_name" ] && already_counted=1 && break
    done
    [ "$already_counted" = "1" ] && continue
    if ! nono_session_running "$NONO_BIN" "$STATE_DIR" "$leftover_name" &&
      ! nono_session_running "$NONO_BIN" "$STATE_DIR" "${leftover_name}-shell"; then
      CANDIDATES+=("$leftover_name")
    fi
  done
  shopt -u nullglob

  case "${#CANDIDATES[@]}" in
  0)
    echo "error: no name given and no live session or leftover $SESSIONS_ROOT/<name> directory found -- pass a name explicitly" >&2
    exit 1
    ;;
  1)
    NAME="${CANDIDATES[0]}"
    echo "==> No name given -- auto-selected '$NAME' (the only candidate)." >&2
    ;;
  *)
    echo "error: no name given and multiple candidates found (${CANDIDATES[*]}) -- pass a name explicitly" >&2
    exit 1
    ;;
  esac
else
  validate_run_name "$NAME"
fi

# require_run_dir's own output (the run dir path) is needed below for the
# live file-sharing release step (RUN_DIR/shared-paths) -- it's allowed
# to be missing here (e.g. a leftover-dir candidate that got cleaned up
# by the OS between discovery and this point, or a --name given for a
# session whose $SESSIONS_ROOT bookkeeping never existed/was already
# swept) -- that just means there's nothing recorded to release, not a
# fatal error, since nothing in this stack is meant to depend on that
# directory surviving (see SESSIONS_ROOT's own comment in lib-common.sh).
RUN_DIR="$SESSIONS_ROOT/$NAME"
if [ ! -d "$RUN_DIR" ]; then
  echo "==> note: no $RUN_DIR bookkeeping directory found -- nothing recorded to release for live-shared paths." >&2
  RUN_DIR=""
fi

# Refuse before touching anything if this run's shell session
# (scripts/shell.sh, `nix run .#shell -- <name>`) is still open -- it
# shares the same XDG_STATE_HOME, so stopping/deleting state here out
# from under it would be surprising.
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
# been released is a no-op for that path. Skipped entirely if $RUN_DIR
# doesn't exist (nothing was ever recorded, or it's already been swept).
if [ -n "$RUN_DIR" ]; then
  while IFS= read -r shared_path; do
    [ -n "$shared_path" ] || continue
    share_release "$shared_path" --self-run "$NAME" || echo "warning: failed to release live share of $shared_path -- restoring ownership/ACLs for it may need to be finished by hand." >&2
  done < <(share_read_paths "$RUN_DIR")
fi

# Clean up the shared nono state dir's contents now that THIS session is
# confirmed stopped -- but ONLY if no other session is live anywhere
# (the state dir is shared by every session now, see IMPLEMENTERS.md's
# "Single nono state dir" section), preserving nono/audit (and the audit
# record subtree) regardless -- everything else under $STATE_DIR is
# disposable scratch state.
if nono_any_session_running "$NONO_BIN" "$STATE_DIR"; then
  echo "==> Other session(s) still live against $STATE_DIR -- not wiping it." >&2
else
  echo "==> No other live sessions -- removing $STATE_DIR contents (preserving nono/audit)..." >&2
  nono_state_wipe_preserving_audit "$STATE_DIR"
  echo "    kept: $STATE_DIR/nono/audit (if present)" >&2
fi

echo "==> Stopped '$NAME'." >&2
