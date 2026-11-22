#!/usr/bin/env bash
# nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#start-agent
#
# Brings up one nono-sandboxed `pi` session as the untrusted `pi` user
# (see nix/mono-flake's `_pi-user-linux.nix`/`_pi-user-darwin.nix` for the
# NOPASSWD+SETENV sudo rule this relies on). See IMPLEMENTERS.md's
# "Launcher and approval helper" section for the full writeup.
#
# High-level flow:
#   1. Re-sync the ONE fixed, shared PI_CODING_AGENT_DIR
#      (/var/lib/pi/.pi/agent -- lib-common.sh's FIXED_AGENT_DIR), and
#      live-share the workdir + any --add/--clone extras with `pi` at
#      their real host paths via ACLs, not a copy (see "Live file
#      sharing" below). This is idempotent and NEVER deletes that
#      directory first -- every launch only adds/overwrites
#      config/extensions/skills on top -- that's what lets `--resume`
#      mean anything, now across EVERY session regardless of --name (the
#      agent dir is no longer per-run). This session's own transient
#      bookkeeping (profile.json, shared-paths, workdir-path, etc.) still
#      lives per-session, but under /tmp (lib-common.sh's SESSIONS_ROOT)
#      rather than /var/lib/pi/runs -- nothing relies on it surviving a
#      reboot/tmp sweep.
#   2. Start the host-side approval helper (outside the sandbox), and read
#      back its webhook URL.
#   3. Generate the launch-ready nono profile (scripts/gen-profile.sh).
#   4. Run `nono run` as `pi` via sudo, with the live-shared workdir as
#      `pi`'s cwd (nono's "workdir").
#
# `pi` gets a LIVE, read-write share of the invoking user's workdir and
# every --add/--clone extra, at their real host paths -- not a copy.
# Access is granted live via ACLs (scripts/lib-common.sh's share_grant)
# and revoked again -- with ownership of anything `pi` left behind
# normalized back to the invoking user -- at shutdown (this script's own
# EXIT trap in foreground mode, the detached wrapper, or `nix run .#stop`).
#
# Every write under /var/lib/pi (the fixed agent dir, and this script's
# own per-session /tmp bookkeeping -- as opposed to the live-shared
# workdir/--add/--clone paths above) still goes through a `sudo -u pi`
# invocation (mkdir/tee/cp); every READ of the invoking user's own files
# (config/agent/ in particular) runs as the invoking user. That split is
# what lets this work without the invoking user ever needing traversal
# rights into pi-owned directories.
set -euo pipefail

# --- PERSONAL_MONOREPO_LOCATION / lib-common.sh ----------------------------
# gen-profile.sh, profiles/work.base.json, and config/agent/ are all read
# directly from the checkout (not re-packaged into the Nix store the way
# this script itself is, via flake.nix's writeShellApplication). gen-profile.sh
# and work.base.json are read directly off disk by this script (running as
# the invoking user), so no `pi`-readability is needed for those two.
# config/agent/ is instead streamed in via a tar pipe (see tar_copy_to_pi
# below), so it doesn't need to be `pi`-readable in place either.
#
# Sources lib-common.sh for STACK_DIR/SESSIONS_ROOT/FIXED_AGENT_DIR and
# the resolve_or_die/resolve_stack_bin/validate_run_name/nono_state_dir/
# nono_state_wipe_preserving_audit/resolve_ca_bundle/share_*/
# git_safe_dir_env helpers.
: "${PERSONAL_MONOREPO_LOCATION:?PERSONAL_MONOREPO_LOCATION must point at the monorepo checkout}"
# shellcheck source=lib-common.sh
# shellcheck disable=SC1091
source "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack/scripts/lib-common.sh"
# shellcheck disable=SC2153 # STACK_DIR is set by the lib-common.sh
# source above, not a misspelling of STATE_DIR (defined much further
# down in this script).
GEN_PROFILE_SH="$STACK_DIR/scripts/gen-profile.sh"
BASE_PROFILE="$STACK_DIR/profiles/work.base.json"
CONFIG_AGENT_DIR="$STACK_DIR/config/agent"
CONFIG_WEB_SEARCH="$STACK_DIR/config/web-search.json"

PROFILE_FLAG="work"
AUDIT_FLAG=0
DETACHED_FLAG=0
NAME_FLAG=""
RESUME_FLAG=0
DRY_RUN=0
ADD_PATHS=()
CLONE_PATHS=()
SECRET_ARGS=() # "NAME=VALUE" pairs from --secret, applied after the namespace scan

print_help() {
  cat <<'EOF'
Usage: start-agent.sh [FLAGS]

Starts one nono-sandboxed `pi` session as the untrusted `pi` user (nix run
.#start-agent). See IMPLEMENTERS.md's "Launcher and approval helper"
section for the full architecture writeup.

Flags:
  --profile work            Which flake-owned nono profile to use. "work"
                             is the only value today (required to be
                             spelled out, to leave room for a future debug
                             profile).
  --audit                    Pass `--audit-integrity` to `nono run`.
  --detached                 Pass `--detached` to `nono run`: the session
                             (and its approval helper) outlive this
                             launcher process -- see "Detached sessions"
                             below. Use the `attach`/`ps`/`stop` wrappers
                             to interact with it.
  --add PATH                 An existing host file or directory, shared
                             LIVE (not copied) read-write at its real
                             host path -- see "Live file sharing" below
                             for what gets refused and how it's torn
                             down (repeatable).
  --clone URL                A URL cloned on the HOST (so host git
                             credentials/ssh-agent are used, not anything
                             inside the sandbox) and then handled exactly
                             like --add (repeatable).
  --secret NAME=VALUE        Inject an already-decrypted secret as an env
                             var into the `pi` process (repeatable). Never
                             appears in argv/`ps` -- see "Secrets" below.
  --name NAME                Session name ROOT (nono's own `--name` is
                             actually NAME-<unix-timestamp>, so repeated
                             launches get distinct nono sessions), and the
                             per-session /tmp bookkeeping directory name
                             ($PI_STACK_SESSIONS_ROOT/NAME-<timestamp>/,
                             default root /tmp/pi-sessions). Default root:
                             "pi". NOTE: the shared PI_CODING_AGENT_DIR
                             (/var/lib/pi/.pi/agent, see "Idempotent
                             per-run seeding / --resume" below) is what
                             actually makes `--resume` meaningful now --
                             it is the SAME directory for every --name,
                             not something this flag selects between.
  --resume                   Forwarded to `pi` itself as `--resume` (pi's
                             own session picker) -- unrelated to nono's own
                             session concept. Mutually exclusive with
                             --name (matches the old container-era
                             semantics).
  --dry-run                  Print the resolved `nono run` command (secret
                             VALUES redacted, names shown) and the paths
                             that would be live-shared, and the ACL
                             actions that would be run for them, then
                             exit. No directories are created, no
                             approval helper is started, no sudo/nono/
                             setfacl/chmod commands run.
  --help, -h                 Show this help and exit.

Environment variables:
  PI_SANDBOX__SECRET__<NAME>  Same as --secret NAME=VALUE (scanned first;
                               a --secret flag with the same NAME wins).
  PERSONAL_MONOREPO_LOCATION   Path to the monorepo checkout (required).
  PI_STACK_NONO_BIN, PI_STACK_PI_BIN, PI_STACK_JQ_BIN,
  PI_STACK_APPROVAL_HELPER_BIN
                               Absolute store paths for nono/pi/jq/the
                               approval helper, set automatically by
                               flake.nix's apps.start-agent wrapper (this
                               flake provisions nono+pi itself, from
                               nixpkgs-unstable). Only needed manually if
                               running this script directly instead of via
                               'nix run .#start-agent' -- otherwise falls
                               back to 'command -v' with a warning.
  PI_STACK_CA_BUNDLE           Explicit override for the host CA bundle
                               granted (read-only, parent directory) into
                               the session and exported as SSL_CERT_FILE/
                               NIX_SSL_CERT_FILE/NODE_EXTRA_CA_CERTS --
                               see resolve_ca_bundle's own comment above
                               for the full resolution order (falls back
                               through NIX_SSL_CERT_FILE, SSL_CERT_FILE,
                               then the usual system bundle paths).
  PI_STACK_EXTRA_PKGS,
  PI_STACK_EXTRA_PATH          Space-separated store paths of flake.nix's
                               ad-hoc `extraPackages` list (currently just
                               coreutils) and the corresponding bin/ PATH
                               (pkgs.lib.makeBinPath), set automatically by
                               flake.nix's apps.start-agent wrapper. The
                               packages are read-granted the same way
                               PI_STACK_PI_BIN is, and the PATH is
                               prepended onto the sandboxed `pi` process's
                               PATH. Tolerated unset.

Live file sharing (workdir, --add, --clone):
  Your current working directory (nono's own "workdir") and every
  --add/--clone extra are shared LIVE and read-write at their REAL host
  path -- not copied anywhere -- via ACLs (POSIX ACLs/setfacl on Linux,
  NFSv4-style ACLs/chmod +a on macOS). A path is refused outright (before anything is granted, for ANY of the paths
  involved) if it's "/", your entire $HOME, or not owned by you. At
  shutdown -- this launcher's own exit (foreground), the detached
  wrapper once the session ends (detached), or `nix run .#stop -- <name>`
  -- every granted path has `pi`-left-behind file ownership normalized
  back to you and its ACL entries removed, which requires an interactive
  `sudo` prompt (unless another still-running session also needs that
  same path, in which case it's left alone). If a launch is interrupted
  before that teardown runs (e.g. a crash), run `nix run .#stop --
  <name>` afterwards to finish restoring ownership/ACLs. A git repo
  shared this way is also registered as a `safe.directory` for both you
  and `pi` (via GIT_CONFIG_* env vars, never a written .gitconfig), since
  git refuses to operate in a directory it doesn't own by default.

Idempotent per-run seeding / --resume:
  Every launch re-syncs the ONE fixed, shared /var/lib/pi/.pi/agent/
  (PI_CODING_AGENT_DIR, the same directory regardless of --name) from
  config/agent/ plus the pi-extra-extensions/pi-extra-skills build
  outputs -- but it only ever ADDS/overwrites those specific files, never
  deletes that directory first. So anything `pi` itself persists there
  (its own session history, included) survives across EVERY launch,
  whatever --name is given -- that's what makes --resume meaningful.
  --name only affects the nono session name/this launch's own transient
  /tmp bookkeeping (its recorded workdir/--add/--clone paths), which are
  re-shared/merged per --name root as before.

Detached sessions:
  --detached starts TWO things that outlive this launcher process, both
  via `setsid`:
    - the approval helper, run as YOU (the invoking user), not `pi` --
      this is required so it inherits your $TMUX for its `--ui auto`
      tmux-prompter fallback (a helper run as `pi` could never reach your
      tmux server). It fails loudly and non-zero if no usable prompter
      can be found -- see "Approvals over SSH / headless hosts" below.
    - a supervisor (runs as `pi`, logging to
      $PI_STACK_SESSIONS_ROOT/<name>-<timestamp>/supervisor.log, default
      /tmp/pi-sessions/...) that generates the profile,
      runs `nono run --detached`, then polls `nono ps` until the session
      is gone.
  This launcher process waits briefly to confirm the approval helper
  actually came up (and prints its log location) before returning --
  i.e. before "detaching" in the user-visible sense -- and exits non-zero
  with a clear error if it didn't.

Approvals over SSH / headless hosts:
  The approval helper's `--ui auto` selection NEVER silently falls back to
  denying every approval any more. On Linux, it only uses a desktop
  dialog (kdialog) when DISPLAY/WAYLAND_DISPLAY is set AND you are not in
  an SSH session; otherwise it only uses tmux, and only if $TMUX is
  already set (i.e. you are running this command from inside a tmux
  session). If neither is available, the helper refuses to start at all
  and prints an actionable error -- start tmux first (e.g.
  `tmux new -s pi`), then run `start-agent.sh` from inside
  that tmux session, so approvals show up as a tmux command-prompt
  (y/n/s) you can answer. The helper's own prompt timeout (55s) is kept
  below the 60s `timeout_secs` the nono profiles set for the webhook
  backend, so a slow answer still resolves (even to a deny, with a logged
  reason) before nono itself gives up waiting.

See README.md and IMPLEMENTERS.md for the full writeup.
EOF
}

add_extra() {
  local kind="$1" value="$2"
  if [ "$kind" = add ]; then ADD_PATHS+=("$value"); else CLONE_PATHS+=("$value"); fi
}

handle_add() {
  local p="${1:?--add requires a PATH argument}"
  if [ ! -e "$p" ]; then
    echo "error: --add path does not exist: $p" >&2
    exit 1
  fi
  add_extra add "$(realpath "$p")"
}

handle_clone() {
  local url="${1:?--clone requires a URL argument}" repo_name clones_dir dest
  repo_name="$(basename "$url")"
  repo_name="${repo_name%.git}"
  if [ -z "$repo_name" ]; then
    echo "error: --clone could not derive a repo name from URL: $url" >&2
    exit 1
  fi
  clones_dir="${XDG_CACHE_HOME:-$HOME/.cache}/pi-sandbox/clones"
  mkdir -p "$clones_dir"
  dest="$clones_dir/$repo_name"
  if [ -d "$dest/.git" ]; then
    echo "==> --clone: $repo_name already cloned at $dest -- fetching only." >&2
    git -C "$dest" fetch
  else
    echo "==> --clone: cloning $url into $dest..." >&2
    git clone "$url" "$dest"
  fi
  add_extra clone "$dest"
}

while [ $# -gt 0 ]; do
  case "$1" in
  --help | -h)
    print_help
    exit 0
    ;;
  --profile)
    PROFILE_FLAG="${2:?--profile requires an argument}"
    shift 2
    ;;
  --profile=*)
    PROFILE_FLAG="${1#--profile=}"
    shift
    ;;
  --audit)
    AUDIT_FLAG=1
    shift
    ;;
  --detached)
    DETACHED_FLAG=1
    shift
    ;;
  --name)
    NAME_FLAG="${2:?--name requires a NAME argument}"
    shift 2
    ;;
  --name=*)
    NAME_FLAG="${1#--name=}"
    shift
    ;;
  --resume)
    RESUME_FLAG=1
    shift
    ;;
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  --add)
    handle_add "${2:?--add requires a PATH argument}"
    shift 2
    ;;
  --add=*)
    handle_add "${1#--add=}"
    shift
    ;;
  --clone)
    handle_clone "${2:?--clone requires a URL argument}"
    shift 2
    ;;
  --clone=*)
    handle_clone "${1#--clone=}"
    shift
    ;;
  --secret)
    secret_arg="${2:?--secret requires a NAME=VALUE argument}"
    secret_name="${secret_arg%%=*}"
    if [ -z "$secret_name" ] || [ "$secret_arg" = "${secret_arg#*=}" ]; then
      echo "error: --secret requires a NAME=VALUE argument with a non-empty NAME (got: $secret_arg)" >&2
      exit 1
    fi
    SECRET_ARGS+=("$secret_arg")
    shift 2
    ;;
  --secret=*)
    secret_arg="${1#--secret=}"
    secret_name="${secret_arg%%=*}"
    if [ -z "$secret_name" ] || [ "$secret_arg" = "${secret_arg#*=}" ]; then
      echo "error: --secret requires a NAME=VALUE argument with a non-empty NAME (got: $secret_arg)" >&2
      exit 1
    fi
    SECRET_ARGS+=("$secret_arg")
    shift
    ;;
  *)
    echo "error: unrecognized argument: $1" >&2
    exit 1
    ;;
  esac
done

if [ "$PROFILE_FLAG" != "work" ]; then
  echo "error: --profile only supports 'work' in this MVP (got: $PROFILE_FLAG)" >&2
  exit 1
fi
if [ "$RESUME_FLAG" = "1" ] && [ -n "$NAME_FLAG" ]; then
  echo "error: --resume and --name are mutually exclusive." >&2
  exit 1
fi

SESSION_NAME_ROOT="${NAME_FLAG:-pi}"
DATE="$(date +%s)"
SESSION_NAME="${SESSION_NAME_ROOT}-${DATE}"
validate_run_name "$SESSION_NAME"
echo "==> Session name: $SESSION_NAME" >&2

# --- Live file sharing: check every path BEFORE granting anything --------
# share_path_check runs no sudo/ACL commands (plain realpath/stat), so
# it's safe to always run (even under --dry-run) -- a refusal here is
# reported immediately, before any of the slower per-run seeding below
# even starts. Order matters: the workdir goes first, so it's always the
# first entry recorded in $RUN_DIR/shared-paths.
WORKDIR="$(share_path_check "$(pwd)")"
CHECKED_ADD_PATHS=()
for add_path in "${ADD_PATHS[@]:-}"; do
  [ -n "$add_path" ] || continue
  CHECKED_ADD_PATHS+=("$(share_path_check "$add_path")")
done
ADD_PATHS=("${CHECKED_ADD_PATHS[@]:-}")
CHECKED_CLONE_PATHS=()
for clone_path in "${CLONE_PATHS[@]:-}"; do
  [ -n "$clone_path" ] || continue
  CHECKED_CLONE_PATHS+=("$(share_path_check "$clone_path")")
done
CLONE_PATHS=("${CHECKED_CLONE_PATHS[@]:-}")
SHARE_PATHS=("$WORKDIR")
for add_path in "${ADD_PATHS[@]:-}"; do
  [ -n "$add_path" ] || continue
  SHARE_PATHS+=("$add_path")
done
for clone_path in "${CLONE_PATHS[@]:-}"; do
  [ -n "$clone_path" ] || continue
  SHARE_PATHS+=("$clone_path")
done

# git_safe_dir_env: registers every shared path as a git safe.directory
# for both the invoking user and `pi` (harmless for paths that aren't
# git repos at all -- git simply never consults an irrelevant
# safe.directory entry). The resulting GIT_CONFIG_* vars are threaded
# through `sudo --preserve-env` below so they reach the `pi` process
# sudo starts, and profiles/work.base.json allow-lists GIT_CONFIG_COUNT/
# GIT_CONFIG_KEY_*/GIT_CONFIG_VALUE_* (top-level environment.allow_vars
# and the nix command's sandboxed environment.allow_vars) so they also
# reach the sandboxed `pi` process itself.
git_safe_dir_env "${SHARE_PATHS[@]}"

# --- Secrets: namespace scan first, then --secret flags (flags win) -------
# Collected as real exported env vars on THIS process (never as `-e`/argv
# tokens anywhere), then threaded through `sudo --preserve-env=<names>`
# below -- never via argv, since that is visible via `ps`.
SECRET_NAMES=()
# `${!PREFIX@}` instead of `compgen -v`: writeShellApplication's bash is
# bashNonInteractive (no readline), which has no compgen builtin.
for var_name in "${!PI_SANDBOX__SECRET__@}"; do
  [ -n "$var_name" ] || continue
  secret_name="${var_name#PI_SANDBOX__SECRET__}"
  export "$secret_name=${!var_name}"
  SECRET_NAMES+=("$secret_name")
done

for secret_arg in "${SECRET_ARGS[@]:-}"; do
  [ -n "$secret_arg" ] || continue
  secret_name="${secret_arg%%=*}"
  secret_value="${secret_arg#*=}"
  export "$secret_name=$secret_value"
  SECRET_NAMES+=("$secret_name")
done

PRESERVE_LIST="PI_CODING_AGENT_DIR,XDG_STATE_HOME"
for secret_name in "${SECRET_NAMES[@]:-}"; do
  [ -n "$secret_name" ] || continue
  PRESERVE_LIST="$PRESERVE_LIST,$secret_name"
done
for git_safe_dir_var in "${GIT_SAFE_DIR_ENV_VARS[@]:-}"; do
  [ -n "$git_safe_dir_var" ] || continue
  PRESERVE_LIST="$PRESERVE_LIST,$git_safe_dir_var"
done

# --- Resolve tool paths, once -----------------------------------------
# This stack's own flake wrapper (flake.nix's apps.start-agent) provisions
# `nono` and `pi` itself (from nixpkgs-unstable, no overlay -- see
# flake.nix's `nono`/`pi-coding-agent` packages) and exports their
# absolute store paths as PI_STACK_*_BIN env vars before this script runs,
# so the normal `nix run .#start-agent` path never touches `command -v`
# for these at all. `resolve_stack_bin` falls back to `command -v` (with a
# warning) only if this script is somehow invoked directly, outside the
# flake wrapper. Resolved to absolute, symlink-free paths and referenced
# that way everywhere below -- both so `nix-store -qR` (inside
# gen-profile.sh) gets real store paths, and so the final `sudo -u pi`
# invocation never depends on whatever (possibly minimal) PATH sudo's
# `secure_path` gives `pi`.
NONO_BIN="$(resolve_stack_bin PI_STACK_NONO_BIN nono)"
PI_BIN="$(resolve_stack_bin PI_STACK_PI_BIN pi)"
JQ_BIN="$(resolve_stack_bin PI_STACK_JQ_BIN jq)"
APPROVAL_HELPER_BIN="$(resolve_stack_bin PI_STACK_APPROVAL_HELPER_BIN approval-helper)"

# --read candidates for gen-profile.sh's Linux exec-ceiling closure --
# this stack's own tools (pi, the nix/scripts tools). node's own files
# come from the `node_runtime` nono group instead (see
# profiles/work.base.json), not from here. agent-validate/
# agent-plan-create are optional -- only added if found, since a plain
# interactive `pi` session (this script's only job) doesn't strictly need
# them the way an IMPLEMENT subagent does.
READ_ROOTS=("$PI_BIN")
for optional_tool in agent-validate agent-plan-create; do
  if tool_path="$(command -v "$optional_tool" 2>/dev/null)"; then
    READ_ROOTS+=("$(readlink -f "$tool_path")")
  fi
done

# --- Ad-hoc extra packages (flake.nix's `extraPackages`, currently just
# coreutils) -- granted read+exec access the same way $PI_BIN is, and
# joined onto PATH inside the sandboxed `pi` process below. Set by
# flake.nix's apps.start-agent wrapper; tolerated unset/empty if this
# script is somehow run directly, outside the flake wrapper (no extra
# packages granted or added to PATH in that case). See IMPLEMENTERS.md.
EXTRA_PKGS="${PI_STACK_EXTRA_PKGS:-}"
for extra_pkg in $EXTRA_PKGS; do
  [ -n "$extra_pkg" ] || continue
  READ_ROOTS+=("$extra_pkg")
done
EXTRA_PATH="${PI_STACK_EXTRA_PATH:-}"

# CA bundle: the sandbox has no default CA trust store reachable inside
# it -- see resolve_ca_bundle above. Its PARENT directory (not the bundle
# file itself) is granted via --read, since it's unverified whether nono
# profiles accept single-file grants (see IMPLEMENTERS.md).
CA_MODE=""
[ "$DRY_RUN" = "1" ] && CA_MODE="dry-run"
CA_BUNDLE="$(resolve_ca_bundle "$CA_MODE")"
CA_BUNDLE_DIR="$(dirname "$CA_BUNDLE")"
READ_ROOTS+=("$CA_BUNDLE_DIR")

READ_ROOT_ARGS=()
for root in "${READ_ROOTS[@]}"; do
  READ_ROOT_ARGS+=(--read "$root")
done

PRESERVE_LIST="$PRESERVE_LIST,SSL_CERT_FILE,NIX_SSL_CERT_FILE,NODE_EXTRA_CA_CERTS"

if [ "$DRY_RUN" = "1" ]; then
  echo "==> --dry-run: no directories created, no helper started, no sudo/nono/setfacl/chmod commands run." >&2
  echo "Resolved (illustrative -- the real webhook URL/profile path are only known once this actually runs):" >&2
  echo "  nono:                $NONO_BIN" >&2
  echo "  pi:                  $PI_BIN" >&2
  echo "  session name:        $SESSION_NAME" >&2
  echo "  workdir (live-shared): $WORKDIR" >&2
  echo "  read roots:          ${READ_ROOTS[*]}" >&2
  echo "  CA bundle:           $CA_BUNDLE (parent dir $CA_BUNDLE_DIR read-granted)" >&2
  echo "  extra packages:      ${EXTRA_PKGS:-<none>}" >&2
  echo "  extra PATH prefix:   ${EXTRA_PATH:-<none>}" >&2
  echo "  --add (live-shared): ${ADD_PATHS[*]:-<none>}" >&2
  echo "  --clone (live-shared, as --add): ${CLONE_PATHS[*]:-<none>}" >&2
  echo "  secrets (names only, values redacted): ${SECRET_NAMES[*]:-<none>}" >&2
  echo >&2
  echo "Live-sharing actions that would be run for each of: ${SHARE_PATHS[*]}" >&2
  case "$(uname -s)" in
  Linux)
    echo "  setfacl -R -m u:pi:rwX <path>; on directories also: find <path> -type d -exec setfacl -m d:u:pi:rwX {} +; find <path> -type d -exec setfacl -m d:u:$(id -un):rwX {} +" >&2
    echo "  setfacl -m u:pi:x <each parent dir of <path>, up to (excluding) '/'>" >&2
    ;;
  Darwin)
    echo "  chmod -R +a 'user:pi allow ...' <path>; chmod -R +a 'user:$(id -un) allow ...' <path>" >&2
    echo "  chmod +a 'user:pi allow search' <each parent dir of <path>, up to (excluding) '/'>" >&2
    ;;
  esac
  echo >&2
  echo "Resolved command (would run as the 'pi' user):" >&2
  nono_run_line="  $NONO_BIN run --profile $SESSIONS_ROOT/$SESSION_NAME/profile.json --allow-cwd"
  [ "$AUDIT_FLAG" = "1" ] && nono_run_line="$nono_run_line --audit-integrity"
  [ "$DETACHED_FLAG" = "1" ] && nono_run_line="$nono_run_line --detached"
  nono_run_line="$nono_run_line --name $SESSION_NAME -- $PI_BIN"
  [ "$RESUME_FLAG" = "1" ] && nono_run_line="$nono_run_line --resume"
  {
    echo "  sudo -u pi --preserve-env=$PRESERVE_LIST -- \\"
    echo "    sh -c \"cd \\\"\$1\\\"; shift; export PATH=\\\"${EXTRA_PATH:+$EXTRA_PATH:}\$PATH\\\"; exec \\\"\$@\\\"\" sh $WORKDIR \\"
    echo "$nono_run_line"
  } >&2
  exit 0
fi

# --- Per-session transient bookkeeping (/tmp) + the ONE fixed, shared,
# pi-owned agent dir -------------------------------------------------------
# RUN_DIR: this launch's own transient scratch (profile.json,
# shared-paths, workdir-path, state/sessions, supervisor files) -- lives
# under SESSIONS_ROOT (/tmp by default), not relied on to survive a
# reboot/tmp sweep (a live nono session is always independently
# discoverable via `nono ps` against the shared NONO_STATE_DIR below).
# AGENT_DIR: the ONE fixed, persistent PI_CODING_AGENT_DIR shared by every
# session regardless of --name (lib-common.sh's FIXED_AGENT_DIR) -- never
# deleted, only ever added/overwritten below, which is what makes
# `--resume` meaningful now. NONO_STATE_DIR is likewise the ONE shared
# nono XDG_STATE_HOME every session uses (lib-common.sh's nono_state_dir).
RUN_DIR="$SESSIONS_ROOT/$SESSION_NAME"
AGENT_DIR="$FIXED_AGENT_DIR"
STATE_DIR="$RUN_DIR/state"
NONO_STATE_DIR="$(nono_state_dir)"

# Wipe the shared nono state dir before launch, but ONLY if nothing is
# currently live against it -- a live sibling session's own state must
# never be torn out from under it just because a new, unrelated session
# is starting. See lib-common.sh's nono_any_session_running for the
# "any output from nono ps counts as live" caveat (nono ps's exact
# "nothing running" output isn't documented in this checkout).
if [ -d "$NONO_STATE_DIR" ]; then
  if nono_any_session_running "$NONO_BIN" "$NONO_STATE_DIR"; then
    echo "==> Other session(s) already live against $NONO_STATE_DIR -- not wiping it before this launch." >&2
  else
    echo "==> No live sessions -- wiping shared nono state dir $NONO_STATE_DIR before launch (preserving nono/audit)..." >&2
    nono_state_wipe_preserving_audit "$NONO_STATE_DIR"
  fi
fi

# tar_copy_to_pi: streams the CONTENTS of a host directory (or a lone
# file) owned by the invoking user into a fresh pi-owned destination
# directory, without ever requiring `pi` to have read access to the
# source in place, and without requiring the invoking user to have any
# access into /var/lib/pi beyond running `sudo -u pi`. The source-side tar
# runs as the invoking user (who already owns/can read these files); only
# the destination-side tar runs as `pi`.
tar_copy_to_pi() {
  local src="$1" dest="$2"
  sudo -u pi mkdir -p "$dest"
  if [ -d "$src" ]; then
    tar -cf - -C "$src" . | sudo -u pi tar -xf - -C "$dest"
  else
    tar -cf - -C "$(dirname "$src")" "$(basename "$src")" | sudo -u pi tar -xf - -C "$dest"
  fi
}

# write_as_pi: pipes $2's contents into a pi-owned file at $1 (the
# invoking user never needs write access into /var/lib/pi for this --
# only `tee`, running as `pi`, does).
write_as_pi() {
  # shellcheck disable=SC2024 # intentional: the invoking user's shell
  # opens $2 for reading before exec'ing sudo -- `pi` never needs read
  # access to it, only `tee`'s write to $1 runs as `pi`.
  sudo -u pi tee "$1" <"$2" >/dev/null
}

echo "==> Seeding the shared agent dir $AGENT_DIR and this session's own transient state under $RUN_DIR (idempotent -- existing pi/session state is kept)..." >&2
sudo -u pi mkdir -p "$AGENT_DIR/extensions" "$AGENT_DIR/skills" "$STATE_DIR/sessions" "$NONO_STATE_DIR"

# --- Live file sharing: grant, then record what was granted ---------------
# Every path in $SHARE_PATHS was already checked (share_path_check, see
# above) before any per-run state was even created. Granted in order
# (workdir first); if any grant fails partway through, everything
# granted so far this launch is released again (best-effort,
# interactive sudo allowed -- this launcher still has a controlling
# terminal at this point in both foreground and detached mode) before
# exiting non-zero, so a failed launch never leaves a half-shared
# workdir/extra behind.
echo "==> Live-sharing ${#SHARE_PATHS[@]} path(s) with 'pi': ${SHARE_PATHS[*]}" >&2
GRANTED_PATHS=()
for share_path in "${SHARE_PATHS[@]}"; do
  if ! share_grant "$share_path"; then
    echo "error: failed to live-share $share_path with 'pi' -- rolling back ${#GRANTED_PATHS[@]} already-granted path(s)." >&2
    for granted_path in "${GRANTED_PATHS[@]:-}"; do
      [ -n "$granted_path" ] || continue
      share_release "$granted_path" || true
    done
    exit 1
  fi
  GRANTED_PATHS+=("$share_path")
done
# Recorded AFTER every grant succeeds (merging -- deduping -- with
# whatever was already recorded for this run name, e.g. across a
# `--resume` relaunch), so a run's shared-paths file never lists a path
# that didn't actually get granted.
share_record_paths "$RUN_DIR" "${SHARE_PATHS[@]}"
share_write_workdir_path "$RUN_DIR" "$WORKDIR"

echo "    building pi-extra-extensions/pi-extra-skills..." >&2
EXTRA_EXT_PATH="$(nix build "$STACK_DIR#pi-extra-extensions" --no-link --print-out-paths)"
EXTRA_SKILLS_PATH="$(nix build "$STACK_DIR#pi-extra-skills" --no-link --print-out-paths)"
# Nix store paths are world-readable, so `pi` can read them directly --
# only the destination write needs to run as `pi`.
sudo -u pi cp -r --no-preserve=mode "$EXTRA_EXT_PATH/." "$AGENT_DIR/extensions/"
sudo -u pi cp -r --no-preserve=mode "$EXTRA_SKILLS_PATH/." "$AGENT_DIR/skills/"

echo "    layering config/agent/ (fresh settings.json/AGENTS.md/agents/*)..." >&2
tar_copy_to_pi "$CONFIG_AGENT_DIR" "$AGENT_DIR"
if [ -f "$CONFIG_WEB_SEARCH" ]; then
  sudo -u pi mkdir -p "$(dirname "$FIXED_WEB_SEARCH_FILE")"
  write_as_pi "$FIXED_WEB_SEARCH_FILE" "$CONFIG_WEB_SEARCH"
fi

# --workdir is passed separately (below, per mode); --add/--clone extras
# are both passed to gen-profile.sh as --add (identical read-write grant
# treatment there -- see gen-profile.sh's own "Step 4" comment), since
# both are now live-shared at their real host path rather than copied
# into a per-run add-N/clone-N destination.
#
# $FIXED_PI_HOME (/var/lib/pi/.pi, covering both AGENT_DIR and
# FIXED_WEB_SEARCH_FILE), /tmp (this session's own transient bookkeeping
# under SESSIONS_ROOT), and every resolved shell-environment grant
# (resolve_shell_env_grants -- /etc/profile/-bashrc and whatever they
# `source`, resolved to their real, symlink-free targets rather than
# hardcoded, since nix-darwin's versions churn on every nixpkgs bump) are
# ALL granted here, in this ONE shared EXTRA_GEN_ARGS array used by BOTH
# the foreground branch below AND the --detached branch's GEN_ARGS_QUOTED
# further down -- not just a foreground-only extra --add list -- so both
# foreground AND --detached sessions actually get the same access (the
# old equivalent grants, --add "$RUNS_ROOT" and the shell-environment
# --add flags, lived ONLY in the foreground branch's gen-profile.sh
# invocation; --detached sessions never got them).
EXTRA_GEN_ARGS=(--add "$FIXED_PI_HOME" --add "/tmp")
while IFS= read -r shell_env_path; do
  [ -n "$shell_env_path" ] || continue
  EXTRA_GEN_ARGS+=(--add "$shell_env_path")
done < <(resolve_shell_env_grants | awk '!seen[$0]++')
for add_path in "${ADD_PATHS[@]:-}"; do
  [ -n "$add_path" ] || continue
  EXTRA_GEN_ARGS+=(--add "$add_path")
done
for clone_path in "${CLONE_PATHS[@]:-}"; do
  [ -n "$clone_path" ] || continue
  EXTRA_GEN_ARGS+=(--add "$clone_path")
done

if [ "$DETACHED_FLAG" != "1" ]; then
  # --- Foreground mode: approval helper and nono share this process's
  # lifetime. ---------------------------------------------------------
  INFO_FILE="$(mktemp -u)"
  HELPER_PID=""
  # shellcheck disable=SC2329 # invoked indirectly via `trap ... EXIT` below
  stop_helper() {
    if [ -n "$HELPER_PID" ] && kill -0 "$HELPER_PID" 2>/dev/null; then
      kill "$HELPER_PID" 2>/dev/null || true
    fi
    rm -f "$INFO_FILE"
    # Release every live-shared path recorded for this run (workdir +
    # every --add/--clone extra) -- interactive sudo is fine here, this
    # launcher still owns a controlling terminal. --self-run excludes
    # THIS run from its own "still live elsewhere" check (its own
    # session is ending right now); a release failure is logged but
    # doesn't abort the rest of the trap (every remaining path still
    # gets a release attempt, and the overall EXIT code is unaffected --
    # `nix run .#stop -- <name>` can always finish the job later).
    local shared_path
    while IFS= read -r shared_path; do
      [ -n "$shared_path" ] || continue
      share_release "$shared_path" --self-run "$SESSION_NAME" || echo "warning: failed to release live share of $shared_path -- run 'nix run .#stop -- $SESSION_NAME' to finish restoring ownership/ACLs." >&2
    done < <(share_read_paths "$RUN_DIR")
  }
  trap stop_helper EXIT

  "$APPROVAL_HELPER_BIN" --ui auto --info-file "$INFO_FILE" --parent-pid "$$" &
  HELPER_PID=$!
  for _ in $(seq 1 50); do
    [ -s "$INFO_FILE" ] && break
    # The helper now fails loudly (non-zero exit, no silent deny-all
    # fallback) when `--ui auto` can't find a usable prompter -- most
    # commonly over SSH with no tmux session to talk to. Detect that exit
    # immediately instead of waiting out the whole poll loop first.
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

  echo "==> Generating the nono profile..." >&2
  TMP_PROFILE="$(mktemp)"
  # $FIXED_PI_HOME, /tmp, and every resolved shell-environment grant are
  # already in EXTRA_GEN_ARGS, above -- shared with the --detached branch
  # further down, nothing hardcoded or foreground-only left here.
  "$GEN_PROFILE_SH" --base "$BASE_PROFILE" --out "$TMP_PROFILE" \
    --webhook-url "$WEBHOOK_URL" --workdir "$WORKDIR" --state-dir "$STATE_DIR" \
    "${EXTRA_GEN_ARGS[@]}" "${READ_ROOT_ARGS[@]}"
  write_as_pi "$RUN_DIR/profile.json" "$TMP_PROFILE"
  rm -f "$TMP_PROFILE"

  export PI_CODING_AGENT_DIR="$AGENT_DIR"
  export XDG_STATE_HOME="$NONO_STATE_DIR"
  export SSL_CERT_FILE="$CA_BUNDLE"
  export NIX_SSL_CERT_FILE="$CA_BUNDLE"
  export NODE_EXTRA_CA_CERTS="$CA_BUNDLE"

  NONO_ARGS=(run --profile "$RUN_DIR/profile.json" --allow-cwd)
  [ "$AUDIT_FLAG" = "1" ] && NONO_ARGS+=(--audit-integrity)
  NONO_ARGS+=(--name "$SESSION_NAME" -- "$PI_BIN")
  [ "$RESUME_FLAG" = "1" ] && NONO_ARGS+=(--resume)

  echo "==> Starting nono as 'pi' (session: $SESSION_NAME)..." >&2
  sudo -u pi --preserve-env="$PRESERVE_LIST" -- \
    sh -c "cd \"\$1\"; shift; export PATH=\"${EXTRA_PATH:+$EXTRA_PATH:}\$PATH\"; exec \"\$@\"" sh "$WORKDIR" \
    "$NONO_BIN" "${NONO_ARGS[@]}"
  exit $?
fi

# --- Detached mode: option A -- the approval helper runs as the INVOKING
# user, not as `pi` ----------------------------------------------------
# Why: the helper needs to inherit the invoking user's $TMUX (and run as
# the user who actually owns that tmux server) for its `--ui auto`
# tmux-prompter fallback to reach a real terminal at all -- a helper
# started as `pi` (e.g. a supervisor run entirely via `sudo -u pi`, how
# this used to work) can never see or reach the invoking user's tmux
# server, which is exactly why approvals were silently impossible in
# detached mode before this fix.
#
# Lifecycle, three pieces:
#   1. supervisor.sh (pi-owned, runs as `pi`): unchanged in spirit from
#      before, EXCEPT it no longer starts or stops the approval helper
#      itself -- it now takes the already-running helper's webhook URL as
#      its one argument, generates the profile, runs `nono run
#      --detached`, and polls `nono ps` until the session is gone. Its own
#      log still lands at $RUN_DIR/supervisor.log, written as `pi` (the
#      invoking user still has no write access into the pi-owned run
#      directory, so that redirect still has to happen INSIDE the sudo'd
#      process, same as before).
#   2. wrapper.sh (owned and run by the INVOKING user, detached from this
#      launcher's terminal via `setsid`): starts the approval helper
#      itself (inheriting this launcher's environment, including $TMUX),
#      verifies it came up, then runs `sudo -u pi -- supervisor.sh
#      <webhook-url>` IN THE FOREGROUND, and once that returns, kills the
#      helper. The helper's `--parent-pid` points at the wrapper's own
#      $$ (the wrapper runs as the invoking user throughout its life, so
#      the helper's liveness poll -- a plain signal-0 check -- actually
#      works here, unlike pointing it at a `pi`-owned process).
#   3. This launcher (synchronous, still attached to the terminal):
#      starts the wrapper (setsid, backgrounded, disowned) and BLOCKS
#      briefly to confirm the helper actually came up (its info file was
#      written, and the wrapper/helper processes are still alive) before
#      returning control to the user -- i.e. before "detaching" in the
#      user-visible sense. On failure, it prints a clear error (pointing
#      at the wrapper's own log) and exits non-zero, rather than silently
#      leaving a broken detached session behind.
#
# The helper's --info-file (it contains the bearer token) is written
# under a small invoking-user-owned, invoking-user-writable scratch
# directory -- NOT under $RUN_DIR, which is pi-owned and not writable by
# the invoking user -- and removed by the wrapper once the supervisor
# returns and the helper has been stopped.
#
# Sudo note: the wrapper calls `sudo -u pi` AFTER this launcher has
# already detached -- if sudo needed an interactive password prompt at
# that point, it would simply fail (no terminal to prompt on). This
# relies on the same NOPASSWD+SETENV sudo rule IMPLEMENTERS.md already
# documents for every other `sudo -u pi` call in this script; the `sudo
# -v` below is a defensive extra (primes/validates the credential cache
# while we're still attached) documenting that assumption, not something
# this flow depends on to function.
sudo -v

# --- 1. supervisor.sh (pi-owned, runs as `pi`) -------------------------
SUPERVISOR_SCRIPT="$RUN_DIR/supervisor.sh"
TMP_SUPERVISOR="$(mktemp)"
GEN_ARGS_QUOTED="$(printf '%q ' "${EXTRA_GEN_ARGS[@]}" "${READ_ROOT_ARGS[@]}")"
# Precomputed as plain strings (rather than inline conditionals inside the
# heredoc below) so the generated script never needs a conditional
# line-continuation -- much easier to get right than juggling printf/
# backslash escaping inside an already-escaped heredoc.
NONO_RUN_EXTRA_FLAGS=""
[ "$AUDIT_FLAG" = "1" ] && NONO_RUN_EXTRA_FLAGS=" --audit-integrity"
PI_RESUME_SUFFIX=""
[ "$RESUME_FLAG" = "1" ] && PI_RESUME_SUFFIX=" --resume"
cat >"$TMP_SUPERVISOR" <<SUPERVISOR
#!/usr/bin/env bash
set -uo pipefail
WEBHOOK_URL="\${1:?supervisor.sh requires the approval webhook URL as its one argument -- started by wrapper.sh, see start-agent.sh}"

TMP_PROFILE="\$(mktemp)"
"$GEN_PROFILE_SH" --base "$BASE_PROFILE" --out "\$TMP_PROFILE" \\
  --webhook-url "\$WEBHOOK_URL" --workdir "$WORKDIR" --state-dir "$STATE_DIR" \\
  $GEN_ARGS_QUOTED
cp "\$TMP_PROFILE" "$RUN_DIR/profile.json"
rm -f "\$TMP_PROFILE"

export PI_CODING_AGENT_DIR="$AGENT_DIR"
export XDG_STATE_HOME="$NONO_STATE_DIR"
export SSL_CERT_FILE="$CA_BUNDLE"
export NIX_SSL_CERT_FILE="$CA_BUNDLE"
export NODE_EXTRA_CA_CERTS="$CA_BUNDLE"
export PATH="${EXTRA_PATH:+$EXTRA_PATH:}\$PATH"
cd "$WORKDIR"
"$NONO_BIN" run --profile "$RUN_DIR/profile.json" --allow-cwd$NONO_RUN_EXTRA_FLAGS --detached --name "$SESSION_NAME" -- "$PI_BIN"$PI_RESUME_SUFFIX

while "$NONO_BIN" ps 2>/dev/null | grep -q "$SESSION_NAME"; do
  sleep 5
done
SUPERVISOR
write_as_pi "$SUPERVISOR_SCRIPT" "$TMP_SUPERVISOR"
sudo -u pi chmod +x "$SUPERVISOR_SCRIPT"
rm -f "$TMP_SUPERVISOR"

# --- 2. wrapper.sh (invoking-user-owned, runs as the invoking user) ----
# HELPER_STATE_DIR: a fresh, invoking-user-owned, invoking-user-writable
# scratch dir for the helper's --info-file (contains the bearer token --
# removed again once the helper is stopped). Deliberately NOT under
# $RUN_DIR (pi-owned, not writable by the invoking user).
HELPER_STATE_DIR="$(mktemp -d "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/pi-sandbox-helper.XXXXXX")"
HELPER_INFO_FILE="$HELPER_STATE_DIR/approval-helper-info.json"
WRAPPER_FAIL_MARKER="$HELPER_STATE_DIR/wrapper.failed"
# WRAPPER_LOG lives OUTSIDE HELPER_STATE_DIR (which gets rm -rf'd by the
# wrapper once the helper is stopped) so it survives for the user to
# inspect after the detached session ends.
WRAPPER_LOG="$(mktemp --suffix=.log "${TMPDIR:-/tmp}/pi-sandbox-wrapper-$SESSION_NAME.XXXXXX")"
WRAPPER_SCRIPT="$HELPER_STATE_DIR/wrapper.sh"

cat >"$WRAPPER_SCRIPT" <<WRAPPER
#!/usr/bin/env bash
set -uo pipefail
"$APPROVAL_HELPER_BIN" --ui auto --info-file "$HELPER_INFO_FILE" --parent-pid "\$\$" &
HELPER_PID=\$!
for _ in \$(seq 1 50); do
  [ -s "$HELPER_INFO_FILE" ] && break
  if ! kill -0 "\$HELPER_PID" 2>/dev/null; then
    echo "approval helper exited before writing its startup info file -- see the lines above for why (over SSH/headless, it requires tmux: start tmux first, then run start-agent.sh from inside that session so \\\$TMUX is set)." >&2
    touch "$WRAPPER_FAIL_MARKER"
    exit 1
  fi
  sleep 0.1
done
if [ ! -s "$HELPER_INFO_FILE" ]; then
  echo "approval helper never wrote its startup info file within the timeout." >&2
  kill "\$HELPER_PID" 2>/dev/null || true
  touch "$WRAPPER_FAIL_MARKER"
  exit 1
fi
WEBHOOK_URL="\$("$JQ_BIN" -r .url "$HELPER_INFO_FILE")"

# The supervisor.log redirect must happen INSIDE the sudo'd process (as
# \`pi\`): the invoking user (this wrapper) has no write access into
# \$RUN_DIR to open that file itself before exec'ing sudo.
sudo -u pi --preserve-env="$PRESERVE_LIST" -- \\
  bash -c 'exec bash "\$1" "\$2" >"\$3" 2>&1 </dev/null' bash \\
  "$SUPERVISOR_SCRIPT" "\$WEBHOOK_URL" "$RUN_DIR/supervisor.log"

# Release every live-shared path recorded for this run, now that the
# supervisor (and so the nono session it started) has exited --
# --noninteractive, since this wrapper has no controlling terminal to
# prompt on at this point (it was started via setsid, detached from the
# launcher). A failure here is logged to this wrapper's own log (not
# fatal to the wrapper itself) and points at \`nix run .#stop\` to finish
# the job.
export PERSONAL_MONOREPO_LOCATION="$PERSONAL_MONOREPO_LOCATION"
# shellcheck source=lib-common.sh
# shellcheck disable=SC1091
source "$STACK_DIR/scripts/lib-common.sh"
while IFS= read -r shared_path; do
  [ -n "\$shared_path" ] || continue
  share_release "\$shared_path" --self-run "$SESSION_NAME" --noninteractive || echo "warning: failed to release live share of \$shared_path -- run 'nix run .#stop -- $SESSION_NAME' to finish restoring ownership/ACLs." >&2
done < <(share_read_paths "$RUN_DIR")

kill "\$HELPER_PID" 2>/dev/null || true
rm -rf "$HELPER_STATE_DIR"
WRAPPER
chmod +x "$WRAPPER_SCRIPT"

# --- 3. Launch the wrapper, detached, and verify the helper came up
# before this launcher itself returns -----------------------------------
echo "==> --detached: starting the approval helper as you (logs: $WRAPPER_LOG) and a supervisor as 'pi' (logs: $RUN_DIR/supervisor.log)..." >&2
setsid bash "$WRAPPER_SCRIPT" >>"$WRAPPER_LOG" 2>&1 </dev/null &
WRAPPER_PID=$!
disown

for _ in $(seq 1 50); do
  [ -s "$HELPER_INFO_FILE" ] && break
  if [ -e "$WRAPPER_FAIL_MARKER" ] || ! kill -0 "$WRAPPER_PID" 2>/dev/null; then
    echo "error: approval helper failed to start for the detached session -- see $WRAPPER_LOG for its stderr output. Over SSH/headless, it requires tmux: start tmux first (e.g. 'tmux new -s pi'), then run start-agent.sh from inside that tmux session (so \$TMUX is set)." >&2
    exit 1
  fi
  sleep 0.1
done
if [ ! -s "$HELPER_INFO_FILE" ]; then
  echo "error: approval helper never wrote its startup info file within the timeout -- see $WRAPPER_LOG." >&2
  exit 1
fi

echo "==> Detached session '$SESSION_NAME' starting (supervisor: $RUN_DIR/supervisor.log, approval helper: $WRAPPER_LOG). Use the ps/attach/stop wrappers to interact with it." >&2
