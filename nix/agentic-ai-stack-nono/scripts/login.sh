#!/usr/bin/env bash
# nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack-nono#login
#
# Phase 4b of PLAN.md: replaces the old container-era `login` compose
# profile. Runs pi's native OAuth login flow INSIDE nono, as the `pi`
# user, using the minimal profiles/login.base.json profile (no workdir
# copy, no nix daemon, no command_policies -- see IMPLEMENTERS.md).
#
# UNVERIFIED (no nono/pi binary in this environment to confirm against):
#   - Whether `pi` has a non-interactive login subcommand. Nothing under
#     config/agent/ or extensions/README.md in this checkout documents
#     one, so this script simply starts `pi` inside the sandbox and
#     expects the USER to trigger the login flow themselves from inside
#     the resulting TUI session (e.g. a `/login` command, if `pi` has
#     one) -- this script cannot drive that interaction for you.
#   - The exact on-disk path pi writes its resulting auth.json to. This
#     mirrors start-agent.sh's own per-run "state/auth/auth.json" layout
#     (STATE_DIR/auth/auth.json below) per this dispatch's explicit
#     instruction, but that path was not independently confirmed against
#     a real `pi` binary either -- see IMPLEMENTERS.md.
#
# Directory layout, all under /var/lib/pi/login/ (deliberately NOT nested
# under one single parent directory that's itself granted to the sandbox
# -- PI_ROOT itself is never granted, only its subdirectories, so nothing
# here is a *parent* of nono-xdg-state/, matching the "never grant a
# parent of a nono-xdg-state dir" rule noted in IMPLEMENTERS.md):
#   agent/             <- PI_CODING_AGENT_DIR (wiped and recreated FRESH
#                         every run -- login is a one-off flow, not a
#                         --resume'able work session, so there's no
#                         idempotent-seeding story to preserve here)
#   auth/               <- STATE_DIR equivalent (gen-profile.sh --state-dir);
#                         pi's resulting auth.json is expected at
#                         auth/auth.json (see UNVERIFIED above)
#   nono-xdg-state/     <- XDG_STATE_HOME for the nono process itself (same
#                         overlap-avoidance pattern as start-agent.sh)
#   profile.json
set -euo pipefail

: "${PERSONAL_MONOREPO_LOCATION:?PERSONAL_MONOREPO_LOCATION must point at the monorepo checkout}"
# shellcheck source=lib-common.sh
# shellcheck disable=SC1091
source "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack-nono/scripts/lib-common.sh"

GEN_PROFILE_SH="$STACK_DIR/scripts/gen-profile.sh"
LOGIN_BASE_PROFILE="$STACK_DIR/profiles/login.base.json"
CONFIG_AGENT_DIR="$STACK_DIR/config/agent"

PI_ROOT="/var/lib/pi/login"
AGENT_DIR="$PI_ROOT/agent"
AUTH_DIR="$PI_ROOT/auth"
NONO_STATE_DIR="$PI_ROOT/nono-xdg-state"
SHARED_AUTH_DIR="/var/lib/pi/auth"
SHARED_AUTH_FILE="$SHARED_AUTH_DIR/auth.json"

DRY_RUN=0

print_help() {
  cat <<'EOF'
Usage: login.sh [FLAGS]

Runs pi's native OAuth login flow inside a minimal nono session, as the
`pi` user (nix run .#login). On exit, copies the resulting auth.json to
the shared /var/lib/pi/auth/auth.json location that start-agent.sh seeds
into every run's own per-run state (see "Also make start-agent seed
.../auth.json" in IMPLEMENTERS.md).

IMPORTANT: this script does not itself drive the login flow -- it starts
`pi` inside the sandbox and expects you to trigger login from inside the
resulting session yourself (see this file's header comment's UNVERIFIED
section: no non-interactive `pi` login subcommand is documented in this
checkout). Exit the `pi` session normally (e.g. Ctrl-D / its own quit
command) once login has completed, and this script will pick up and copy
the resulting auth.json.

Flags:
  --dry-run    Print the resolved command and exit. No directories are
               created, no approval helper is started, no sudo/nono
               commands run.
  --help, -h   Show this help and exit.

Environment variables:
  PERSONAL_MONOREPO_LOCATION   Path to the monorepo checkout (required).
  PI_STACK_NONO_BIN, PI_STACK_PI_BIN, PI_STACK_JQ_BIN,
  PI_STACK_APPROVAL_HELPER_BIN
                                Absolute store paths, set automatically by
                                flake.nix's apps.login wrapper. Only
                                needed manually if running this script
                                directly instead of via 'nix run .#login'.
EOF
}

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
  *)
    echo "error: unrecognized argument: $1" >&2
    exit 1
    ;;
  esac
done

NONO_BIN="$(resolve_stack_bin PI_STACK_NONO_BIN nono)"
PI_BIN="$(resolve_stack_bin PI_STACK_PI_BIN pi)"
JQ_BIN="$(resolve_stack_bin PI_STACK_JQ_BIN jq)"
APPROVAL_HELPER_BIN="$(resolve_stack_bin PI_STACK_APPROVAL_HELPER_BIN approval-helper)"

if [ "$DRY_RUN" = "1" ]; then
  echo "==> --dry-run: no directories created, no helper started, no sudo/nono commands run." >&2
  echo "Resolved (illustrative -- the real webhook URL/profile path are only known once this actually runs):" >&2
  echo "  nono:   $NONO_BIN" >&2
  echo "  pi:     $PI_BIN" >&2
  echo "  agent:  $AGENT_DIR" >&2
  echo "  auth:   $AUTH_DIR (-> copied to $SHARED_AUTH_FILE on exit)" >&2
  echo >&2
  echo "Resolved command (would run as the 'pi' user):" >&2
  echo "  sudo -u pi --preserve-env=PI_CODING_AGENT_DIR,XDG_STATE_HOME -- \\" >&2
  echo "    sh -c 'cd \"\$1\"; shift; exec \"\$@\"' sh $AGENT_DIR \\" >&2
  echo "    $NONO_BIN run --profile $PI_ROOT/profile.json --allow-cwd --name pi-login -- $PI_BIN" >&2
  exit 0
fi

echo "==> Preparing a fresh /var/lib/pi/login/ (agent/ and auth/ are wiped and recreated -- login is not a --resume'able session)..." >&2
sudo -u pi mkdir -p "$PI_ROOT"
sudo -u pi rm -rf "$AGENT_DIR" "$AUTH_DIR"
sudo -u pi mkdir -p "$AGENT_DIR/extensions" "$AGENT_DIR/skills" "$AUTH_DIR" "$NONO_STATE_DIR"

# write_as_pi: pipes $2's contents into a pi-owned file at $1 -- mirrors
# start-agent.sh's own helper of the same name/shape (duplicated minimally
# here rather than factored into lib-common.sh; see this dispatch's note
# that login-specific duplication should stay minimal/local, not shared).
write_as_pi() {
  # shellcheck disable=SC2024
  sudo -u pi tee "$1" <"$2" >/dev/null
}

echo "    layering config/agent/ onto the fresh login agent dir (settings.json defaults, extensions/skills)..." >&2
tar -cf - -C "$CONFIG_AGENT_DIR" . | sudo -u pi tar -xf - -C "$AGENT_DIR"

# --- Approval helper: duplicated (minimally, not factored) from
# start-agent.sh's foreground-mode block, per this dispatch's note that
# this duplication should stay local rather than be pulled into
# lib-common.sh. ---------------------------------------------------------
INFO_FILE="$(mktemp -u)"
HELPER_PID=""
# shellcheck disable=SC2329
stop_helper() {
  if [ -n "$HELPER_PID" ] && kill -0 "$HELPER_PID" 2>/dev/null; then
    kill "$HELPER_PID" 2>/dev/null || true
  fi
  rm -f "$INFO_FILE"
}
trap stop_helper EXIT

"$APPROVAL_HELPER_BIN" --ui auto --info-file "$INFO_FILE" --parent-pid "$$" &
HELPER_PID=$!
for _ in $(seq 1 50); do
  [ -s "$INFO_FILE" ] && break
  sleep 0.1
done
if [ ! -s "$INFO_FILE" ]; then
  echo "error: approval helper never wrote its startup info file -- check its stderr output above." >&2
  exit 1
fi
WEBHOOK_URL="$("$JQ_BIN" -r .url "$INFO_FILE")"

echo "==> Generating the nono login profile..." >&2
TMP_PROFILE="$(mktemp)"
"$GEN_PROFILE_SH" --base "$LOGIN_BASE_PROFILE" --out "$TMP_PROFILE" \
  --webhook-url "$WEBHOOK_URL" --workdir "$AGENT_DIR" --state-dir "$AUTH_DIR" \
  --extra-closure-root "$PI_BIN"
write_as_pi "$PI_ROOT/profile.json" "$TMP_PROFILE"
rm -f "$TMP_PROFILE"

export PI_CODING_AGENT_DIR="$AGENT_DIR"
export XDG_STATE_HOME="$NONO_STATE_DIR"

echo "==> Starting pi inside nono for login. Trigger pi's own login flow from" >&2
echo "    inside the session (e.g. a '/login' command, if pi has one -- UNVERIFIED," >&2
echo "    see this script's --help); exit the session normally once done." >&2
sudo -u pi --preserve-env=PI_CODING_AGENT_DIR,XDG_STATE_HOME -- \
  sh -c 'cd "$1"; shift; exec "$@"' sh "$AGENT_DIR" \
  "$NONO_BIN" run --profile "$PI_ROOT/profile.json" --allow-cwd --name pi-login -- "$PI_BIN"

LOGIN_AUTH_FILE="$AUTH_DIR/auth.json"
if sudo -u pi test -f "$LOGIN_AUTH_FILE"; then
  sudo -u pi mkdir -p "$SHARED_AUTH_DIR"
  sudo -u pi sh -c 'install -m 0600 "$1" "$2"' sh "$LOGIN_AUTH_FILE" "$SHARED_AUTH_FILE"
  echo "==> Copied login auth to $SHARED_AUTH_FILE (future runs seed it automatically -- see start-agent.sh)." >&2
else
  echo "warning: no auth.json found at $LOGIN_AUTH_FILE after the login session exited -- login may not have completed. Nothing was copied to $SHARED_AUTH_FILE." >&2
fi
