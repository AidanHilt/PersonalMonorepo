#!/usr/bin/env bash
# nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#shell -- <name>
#
# Opens a separate, interactive bash shell inside a nono sandbox for the
# run at /var/lib/pi/runs/<name>/, using that run's own nono
# XDG_STATE_HOME (lib-common.sh's nono_state_dir_for) and a COPY of that
# run's own profile.json (only the webhook approval URL rewritten --
# never regenerated from scratch via gen-profile.sh).
#
# Why this exists: `nix run .#attach -- <name>` attaches to pi's own TUI
# PTY, not a plain shell, and fails outright for a foreground run
# ("Session <name> already has an active attached client"). This script
# instead starts its OWN nono session ("<name>-shell") with its OWN
# approval helper (started as the invoking user), so it works whether or
# not the run's own pi session/helper is still alive.
#
# One shell per run: refuses to start if a "<name>-shell" session is
# already running. `nix run .#stop -- <name>` also refuses to stop/delete
# this run's state while its shell session is still open -- see stop.sh.
#
# Live file sharing: re-shares (lib-common.sh's share_grant, not a
# re-copy) the run's own recorded workdir and --add/--clone extras for
# the lifetime of this shell session, releasing them again on exit --
# but never while the run's own main ("<name>") session is still live
# and also shares that path.
set -euo pipefail

print_help() {
  cat <<'EOF'
Usage: shell.sh [--help] [--dry-run] <name>

Opens a separate, interactive bash shell inside a nono sandbox for the
run at /var/lib/pi/runs/<name>/ (nono session "<name>-shell", sharing
that run's own XDG_STATE_HOME with its pi session). Uses a per-invocation
COPY of that run's own profile.json
(/var/lib/pi/runs/<name>/shell-profile.json, regenerated on every call --
only its webhook approval URL is rewritten; the run's own profile.json is
never modified). Starts its own approval helper (as you, the invoking
user, --ui auto), independent of whether the run's own pi session/helper
is still alive.

Re-shares (not re-copies) the run's own recorded workdir and every
--add/--clone extra with `pi` for the lifetime of this shell session
(idempotent alongside the run's own main session), and releases them
again on exit -- except a path still shared by the run's own MAIN
session, which is left alone (closing this shell never pulls access out
from under a still-running agent session). See IMPLEMENTERS.md's "Live
file sharing" section for the full model.

Only one shell session per run is allowed at a time: if "<name>-shell" is
already running, this refuses to start a second one. `nix run .#stop --
<name>` also refuses to stop the run (or delete its state) while a shell
session is open -- exit the shell first.

Positional arguments:
  <name>   The run/session name (as passed to start-agent.sh --name, or
           "pi" if that run used the default). The run must already
           exist with a profile.json -- start it with `nix run
           .#start-agent` first.

Flags:
  --dry-run    Print the resolved command and exit. No directories are
               created, no approval helper is started, no sudo/nono
               commands run -- this also means the "already running"
               check and the profile.json existence check below are both
               SKIPPED in --dry-run mode (both require a sudo call).
  --help, -h   Show this help and exit.

Approvals over SSH / headless hosts:
  Same `--ui auto` requirements as start-agent.sh/login.sh: on Linux, a
  desktop dialog is only used when DISPLAY/WAYLAND_DISPLAY is set AND you
  are not in an SSH session; otherwise the helper only uses tmux, and
  only if $TMUX is already set. If neither is available, the helper
  refuses to start at all -- start tmux first (e.g. `tmux new -s pi`),
  then run this command from inside that tmux session.

Environment variables:
  PERSONAL_MONOREPO_LOCATION   Path to the monorepo checkout (required).
  PI_STACK_NONO_BIN, PI_STACK_JQ_BIN, PI_STACK_APPROVAL_HELPER_BIN,
  PI_STACK_BASH_BIN
                                Absolute store paths, set automatically by
                                flake.nix's apps.shell wrapper. Only
                                needed manually if running this script
                                directly instead of via 'nix run .#shell'.
                                PI_STACK_BASH_BIN may be silently
                                overridden at runtime -- see "bash path
                                fallback" below.
  PI_STACK_CA_BUNDLE            Explicit override for the host CA bundle
                                granted (read-only, parent directory) into
                                the shell session and exported as
                                SSL_CERT_FILE/NIX_SSL_CERT_FILE/
                                NODE_EXTRA_CA_CERTS -- see
                                lib-common.sh's resolve_ca_bundle for the
                                full resolution order.
  PI_STACK_EXTRA_PATH            bin/ PATH for flake.nix's ad-hoc
                                `extraPackages` list (currently just
                                coreutils), set automatically by
                                flake.nix's apps.shell wrapper. Prepended
                                onto the sandboxed shell's PATH -- no
                                read-grant change here (this shell reuses
                                the run's own existing profile.json
                                unmodified). Tolerated unset.

bash path fallback:
  flake.nix's apps.shell resolves PI_STACK_BASH_BIN from this flake's own
  nixpkgs (via pkgs.bashInteractive), which may NOT be covered by the
  run's own profile.json filesystem.read grants (those were computed by
  gen-profile.sh against a DIFFERENT nixpkgs closure -- the one
  start-agent.sh resolved pi/nono from). If the resolved bash path isn't
  a prefix match of any entry in the run's profile.json
  filesystem.read list, this script falls back to
  /run/current-system/sw/bin/bash (covered by every profile's implicit
  system-closure grant -- see gen-profile.sh) and prints a note to
  stderr.
EOF
}

DRY_RUN=0
NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
  --help | -h)
    print_help
    exit 0
    ;;
  --dry-run)
    DRY_RUN=1
    shift
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

if [ -z "$NAME" ]; then
  echo "error: usage: shell.sh [--dry-run] <name> (run shell.sh --help for details)" >&2
  exit 1
fi

: "${PERSONAL_MONOREPO_LOCATION:?PERSONAL_MONOREPO_LOCATION must point at the monorepo checkout}"
# shellcheck source=lib-common.sh
# shellcheck disable=SC1091
source "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack/scripts/lib-common.sh"

RUN_DIR="$(require_run_dir "$NAME")"
echo "RUN DIR: ${RUN_DIR}"
STATE_DIR="$(nono_state_dir_for "$NAME")"
SESSION_NAME="${NAME}-shell"
RUN_PROFILE="$RUN_DIR/profile.json"
SHELL_PROFILE="$RUN_DIR/shell-profile.json"
AGENT_DIR="$RUN_DIR/pi/agent"
# WORKDIR/SHARED_PATHS: the run's own live-shared workdir and
# --add/--clone extras, as recorded by start-agent.sh (lib-common.sh's
# share_write_workdir_path/share_record_paths) -- both require a
# `sudo -u pi cat`, so they're read below, AFTER the --dry-run early
# exit (same convention as the "already running"/profile.json existence
# checks this script already skips under --dry-run).
WORKDIR=""
SHARED_PATHS=()

NONO_BIN="$(resolve_stack_bin PI_STACK_NONO_BIN nono)"
JQ_BIN="$(resolve_stack_bin PI_STACK_JQ_BIN jq)"
APPROVAL_HELPER_BIN="$(resolve_stack_bin PI_STACK_APPROVAL_HELPER_BIN approval-helper)"
BASH_BIN="$(resolve_stack_bin PI_STACK_BASH_BIN bash)"

# PI_STACK_EXTRA_PATH: bin/ PATH for flake.nix's ad-hoc `extraPackages`
# list (currently just coreutils, see flake.nix/start-agent.sh/
# IMPLEMENTERS.md), set automatically by flake.nix's apps.shell wrapper.
# No read-grant change here -- this shell reuses the run's own existing
# profile.json, unmodified; only the sandboxed process's own PATH is
# prepended, below. Tolerated unset/empty.
EXTRA_PATH="${PI_STACK_EXTRA_PATH:-}"

CA_MODE=""
[ "$DRY_RUN" = "1" ] && CA_MODE="dry-run"
CA_BUNDLE="$(resolve_ca_bundle "$CA_MODE")"
CA_BUNDLE_DIR="$(dirname "$CA_BUNDLE")"

if [ "$DRY_RUN" = "1" ]; then
  echo "==> --dry-run: no directories created, no helper started, no sudo/nono/setfacl/chmod commands run (including the 'already running' and profile.json existence checks below, and the workdir/shared-paths lookups, which also require sudo -u pi)." >&2
  echo "Resolved (illustrative -- the real webhook URL is only known once this actually runs, and the bash path fallback below is not evaluated in --dry-run):" >&2
  echo "  nono:          $NONO_BIN" >&2
  echo "  bash:          $BASH_BIN" >&2
  echo "  run dir:       $RUN_DIR" >&2
  echo "  state dir:     $STATE_DIR" >&2
  echo "  session name:  $SESSION_NAME" >&2
  echo "  run profile:   $RUN_PROFILE (must already exist -- start the run with 'nix run .#start-agent' first)" >&2
  echo "  shell profile: $SHELL_PROFILE (a copy of the run profile with only its webhook URL rewritten)" >&2
  echo "  workdir:       <recorded in $RUN_DIR/workdir-path by start-agent.sh -- re-shared (not re-copied) with 'pi' on start, released on exit>" >&2
  echo "  shared paths:  <recorded in $RUN_DIR/shared-paths -- all re-shared with 'pi' on start, released on exit>" >&2
  echo "  CA bundle:     $CA_BUNDLE (parent dir $CA_BUNDLE_DIR read-granted; see PI_STACK_CA_BUNDLE below)" >&2
  echo "  extra PATH prefix: ${EXTRA_PATH:-<none>}" >&2
  echo >&2
  echo "Resolved command (would run as the 'pi' user):" >&2
  echo "  sudo -u pi --preserve-env=PI_CODING_AGENT_DIR,XDG_STATE_HOME,SSL_CERT_FILE,NIX_SSL_CERT_FILE,NODE_EXTRA_CA_CERTS,<git safe.directory vars> -- \\" >&2
  echo "    sh -c \"cd \\\"\$1\\\"; shift; export PATH=\\\"${EXTRA_PATH:+$EXTRA_PATH:}\$PATH\\\"; exec \\\"\$@\\\"\" sh <recorded workdir> \\" >&2
  echo "    $NONO_BIN run --profile $SHELL_PROFILE --allow-cwd --name $SESSION_NAME -- $BASH_BIN -i" >&2
  exit 0
fi

if ! sudo -u pi test -f "$RUN_PROFILE"; then
  echo "error: run '$NAME' has no profile.json -- start it with start-agent first" >&2
  exit 1
fi

if nono_session_running "$NONO_BIN" "$STATE_DIR" "$SESSION_NAME"; then
  echo "error: a shell session ('$SESSION_NAME') is already running for run '$NAME' -- only one shell per run is allowed. Exit it before starting another (there is no 'nono attach' target for a plain shell session)." >&2
  exit 1
fi

# --- Live file sharing: re-share this run's recorded workdir/--add/
# --clone paths for the lifetime of this shell session too -- share_grant
# is idempotent, so this is harmless even while the run's own main
# session already has the same paths granted. --------------------------
WORKDIR="$(share_read_workdir_path "$RUN_DIR")"
if [ -z "$WORKDIR" ]; then
  echo "error: run '$NAME' has no recorded workdir (missing $RUN_DIR/workdir-path) -- start it with start-agent first" >&2
  exit 1
fi
while IFS= read -r shared_path; do
  [ -n "$shared_path" ] || continue
  SHARED_PATHS+=("$shared_path")
done < <(share_read_paths "$RUN_DIR")
if [ "${#SHARED_PATHS[@]}" -eq 0 ]; then
  SHARED_PATHS=("$WORKDIR")
fi

for shared_path in "${SHARED_PATHS[@]}"; do
  share_path_check "$shared_path" >/dev/null
done
# Granted in order; if any grant fails partway through, everything
# granted so far for this shell session is released again
# (best-effort, interactive sudo allowed -- this script still owns a
# controlling terminal at this point) before exiting non-zero, mirroring
# start-agent.sh's own grant-rollback loop. The stop_helper EXIT trap is
# installed below, after this loop, so it never double-releases these.
GRANTED_PATHS=()
for shared_path in "${SHARED_PATHS[@]}"; do
  if ! share_grant "$shared_path"; then
    echo "error: failed to live-share $shared_path with 'pi' -- rolling back ${#GRANTED_PATHS[@]} already-granted path(s)." >&2
    for granted_path in "${GRANTED_PATHS[@]:-}"; do
      [ -n "$granted_path" ] || continue
      share_release "$granted_path" --self-run "$NAME" --treat-self-main-live || true
    done
    exit 1
  fi
  GRANTED_PATHS+=("$shared_path")
done
git_safe_dir_env "${SHARED_PATHS[@]}"
PRESERVE_LIST="PI_CODING_AGENT_DIR,XDG_STATE_HOME,SSL_CERT_FILE,NIX_SSL_CERT_FILE,NODE_EXTRA_CA_CERTS"
for git_safe_dir_var in "${GIT_SAFE_DIR_ENV_VARS[@]:-}"; do
  [ -n "$git_safe_dir_var" ] || continue
  PRESERVE_LIST="$PRESERVE_LIST,$git_safe_dir_var"
done

# --- Approval helper: this shell gets its OWN helper, independent of the
# run's own pi session/helper -- started exactly like start-agent.sh's
# foreground mode / login.sh, as you (the invoking user), so --ui auto's
# tmux fallback can reach your terminal. -----------------------------
INFO_FILE="$(mktemp -u)"
HELPER_PID=""
# shellcheck disable=SC2329
stop_helper() {
  if [ -n "$HELPER_PID" ] && kill -0 "$HELPER_PID" 2>/dev/null; then
    kill "$HELPER_PID" 2>/dev/null || true
  fi
  rm -f "$INFO_FILE"
  # Release every path re-shared above for this shell session.
  # --self-run "$NAME" --treat-self-main-live: never release a path
  # while the run's own MAIN session ("$NAME", not this shell) is still
  # live and also shares it -- closing this shell must never pull
  # access out from under a still-running agent session. Interactive
  # sudo is fine here, this script still owns a controlling terminal.
  local shared_path
  for shared_path in "${SHARED_PATHS[@]:-}"; do
    [ -n "$shared_path" ] || continue
    share_release "$shared_path" --self-run "$NAME" --treat-self-main-live || echo "warning: failed to release live share of $shared_path -- run 'nix run .#stop -- $NAME' to finish restoring ownership/ACLs." >&2
  done
}
trap stop_helper EXIT

"$APPROVAL_HELPER_BIN" --ui auto --info-file "$INFO_FILE" --parent-pid "$$" &
HELPER_PID=$!
for _ in $(seq 1 50); do
  [ -s "$INFO_FILE" ] && break
  # The helper fails loudly (non-zero exit, no silent deny-all fallback)
  # when `--ui auto` can't find a usable prompter -- most commonly over
  # SSH with no tmux session to talk to. Detect that exit immediately
  # instead of waiting out the whole poll loop first.
  if ! kill -0 "$HELPER_PID" 2>/dev/null; then
    echo "error: approval helper (pid $HELPER_PID) exited before writing its startup info file -- see its stderr output above for why. Over SSH/headless, it requires tmux: start tmux first (e.g. 'tmux new -s pi'), then run this command from inside that tmux session (so \$TMUX is set)." >&2
    exit 1
  fi
  sleep 0.1
done
if [ ! -s "$INFO_FILE" ]; then
  echo "error: approval helper never wrote its startup info file -- check its stderr output above." >&2
  exit 1
fi
WEBHOOK_URL="$("$JQ_BIN" -r .url "$INFO_FILE")"

# write_as_pi: pipes $2's contents into a pi-owned file at $1 -- mirrors
# start-agent.sh's/login.sh's own helper of the same name/shape
# (duplicated minimally here rather than factored into lib-common.sh,
# matching their own precedent of keeping this kind of per-script
# duplication local).
write_as_pi() {
  # shellcheck disable=SC2024
  sudo -u pi tee "$1" <"$2" >/dev/null
}

RUN_PROFILE_JSON="$(mktemp)"
# shellcheck disable=SC2024 # intentional: the redirect (opening
# RUN_PROFILE_JSON for writing) runs as the invoking user, who already
# has write access to this mktemp-created scratch file -- only `cat`'s
# read of the pi-owned $RUN_PROFILE needs to run as `pi`.
sudo -u pi cat "$RUN_PROFILE" >"$RUN_PROFILE_JSON"

# bash path fallback (see this script's --help): if the
# resolved bash path isn't covered by any of the run's own profile.json
# filesystem.read grants, fall back to the system bash instead of
# launching a session that would immediately hit a sandbox exec denial.
BASH_COVERED=0
while IFS= read -r read_root; do
  [ -n "$read_root" ] || continue
  case "$BASH_BIN" in
  "$read_root"*)
    BASH_COVERED=1
    break
    ;;
  esac
done < <("$JQ_BIN" -r '.filesystem.read // [] | .[]' "$RUN_PROFILE_JSON")
if [ "$BASH_COVERED" != "1" ]; then
  echo "==> note: $BASH_BIN is not covered by run '$NAME''s profile.json filesystem.read grants -- falling back to /run/current-system/sw/bin/bash (see shell.sh --help's 'bash path fallback' note)." >&2
  BASH_BIN="/run/current-system/sw/bin/bash"
fi

echo "==> Generating a per-invocation shell profile (copy of $RUN_PROFILE with only its webhook URL rewritten)..." >&2
TMP_PROFILE="$(mktemp)"
# shellcheck disable=SC2016 # $url here is jq's own --arg binding, not a
# shell expansion -- the single quotes are intentional (same idiom
# gen-profile.sh already uses for the same substitution).
"$JQ_BIN" --arg url "$WEBHOOK_URL" \
  '.network.approval_backends.dialog.url = $url' \
  "$RUN_PROFILE_JSON" >"$TMP_PROFILE"
rm -f "$RUN_PROFILE_JSON"
write_as_pi "$SHELL_PROFILE" "$TMP_PROFILE"
rm -f "$TMP_PROFILE"

export PI_CODING_AGENT_DIR="$AGENT_DIR"
export XDG_STATE_HOME="$STATE_DIR"
export SSL_CERT_FILE="$CA_BUNDLE"
export NIX_SSL_CERT_FILE="$CA_BUNDLE"
export NODE_EXTRA_CA_CERTS="$CA_BUNDLE"

echo "==> Starting a bash shell inside nono as 'pi' (session: $SESSION_NAME)..." >&2
sudo -u pi --preserve-env="$PRESERVE_LIST" -- \
  sh -c "cd \"\$1\"; shift; export PATH=\"${EXTRA_PATH:+$EXTRA_PATH:}\$PATH\"; exec \"\$@\"" sh "$WORKDIR" \
  "$NONO_BIN" run --profile "$SHELL_PROFILE" --allow-cwd --name "$SESSION_NAME" -- "$BASH_BIN" -i
