#!/usr/bin/env bash
# lib-common.sh -- shared helpers for the session-wrapper scripts (ps.sh,
# attach.sh, stop.sh, shell.sh, start-agent.sh): resolve_or_die/
# resolve_stack_bin/validate_run_name/nono_state_dir/resolve_ca_bundle,
# plus the live-file-sharing primitives (share_path_check, share_grant,
# share_release and helpers, git_safe_dir_env, and the RUN_DIR/shared-paths
# + RUN_DIR/workdir-path bookkeeping helpers) used to share -- and later
# release -- the invoking user's workdir and every --add/--clone extra LIVE
# at its real host path via ACLs, instead of copying it into a pi-owned
# location. See each function's own comment below, and IMPLEMENTERS.md's
# "Live file sharing" section for the full model.
#
# Must be `source`d (not executed) by a caller that has already run
# `set -euo pipefail` and defines PERSONAL_MONOREPO_LOCATION (same
# convention as every script that sources this file).
#
# shellcheck shell=bash

: "${PERSONAL_MONOREPO_LOCATION:?PERSONAL_MONOREPO_LOCATION must point at the monorepo checkout}"
# shellcheck disable=SC2034 # STACK_DIR is used by scripts that `source`
# this file, not by this file itself.
STACK_DIR="$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack"

# SESSIONS_ROOT: per-session TRANSIENT bookkeeping only (profile.json,
# shell-profile.json, shared-paths, workdir-path, state/sessions,
# supervisor.sh/.log, approval-helper-info.json) -- nothing here is relied
# on surviving a reboot/tmp-cleaner sweep; a session that's still live is
# always discoverable via `nono ps` against the single shared nono state
# dir (see nono_state_dir below), never by this directory existing.
# Overridable via PI_STACK_SESSIONS_ROOT (e.g. for tests). Replaces the
# old /var/lib/pi/runs -- see IMPLEMENTERS.md's "Per-session state layout"
# section.
SESSIONS_ROOT="${PI_STACK_SESSIONS_ROOT:-/tmp/pi-sessions}"

# PI_USER_HOME: the `pi` user's actual home directory -- pi's real, pi-owned
# /var/lib/pi (see nix/mono-flake's `_pi-user.nix`, which sets
# `users.users.pi.home` to exactly this on both Linux and nix-darwin).
# This is what every SANDBOXED process's $HOME must be set to
# explicitly: `sudo -u pi` does not reset $HOME on its own, so without
# this the sandboxed `pi`/(shell) process inherits the INVOKING user's
# home (e.g. /Users/aidan) -- a directory `pi` cannot read, which also
# makes Nix warn about a home directory it doesn't own. Distinct from
# FIXED_PI_HOME below, which is pi's own `.pi` state dir WITHIN this
# home. Host-side work (the launcher's own clone cache, the
# share_path_check "your entire $HOME" guard, git credentials, ACL
# handling) must keep using the INVOKING user's $HOME, never this.
# NOT overridable via env -- pi's home is a flake-owned fact, not a
# per-launch choice.
# shellcheck disable=SC2034 # used by scripts that `source` this file
# (start-agent.sh, shell.sh), not by this file itself.
PI_USER_HOME="/var/lib/pi"

# FIXED_AGENT_DIR / FIXED_PI_HOME: ONE persistent, shared PI_CODING_AGENT_DIR
# for every start-agent.sh/shell.sh session -- replaces the old per-run
# <RUNS_ROOT>/<name>/pi/agent tree. Never deleted by any script in this
# stack (only ever added/overwritten -- see start-agent.sh's seeding
# step); this is what makes `pi --resume` keep working across launches
# now that sessions no longer each get their own state tree. Mirrors pi's
# own default ($HOME/.pi/agent) under the `pi` user's actual home
# ($PI_USER_HOME, i.e. /var/lib/pi), on the theory that this is the path
# pi's own code (e.g. the web-search feature) most likely assumes a
# sibling web-search.json lives next to -- an inference, since pi's own
# source isn't vendored in this checkout. NOT overridable via env -- this
# is a flake-owned, fixed location, not a per-launch choice.
FIXED_PI_HOME="/var/lib/pi/.pi"
# shellcheck disable=SC2034 # used by scripts that `source` this file
# (start-agent.sh, shell.sh), not by this file itself.
FIXED_AGENT_DIR="$FIXED_PI_HOME/agent"
# shellcheck disable=SC2034 # used by start-agent.sh, not by this file
# itself.
FIXED_WEB_SEARCH_FILE="$FIXED_PI_HOME/web-search.json"

# resolve_or_die: resolves $1 to an absolute, symlink-free path via
# `command -v`, or exits with an error if it isn't found on PATH.
resolve_or_die() {
  local name="$1" path
  if ! path="$(command -v "$name" 2>/dev/null)"; then
    echo "error: required tool not found on PATH: $name" >&2
    exit 1
  fi
  readlink -f "$path"
}

# resolve_stack_bin: prefers the absolute store path exported by the flake
# wrapper (PI_STACK_*_BIN -- see flake.nix's app wrappers, mirroring
# start-agent.sh's own resolve_stack_bin). Falls back to `command -v
# $name` on the invoking user's PATH ONLY when run directly outside the
# flake, with a warning pointing at the supported `nix run .#<app>`
# entrypoint.
resolve_stack_bin() {
  local env_var="$1" name="$2" value="${!1:-}"
  if [ -n "$value" ]; then
    readlink -f "$value"
    return 0
  fi
  echo "warning: $env_var not set -- falling back to 'command -v $name' on this shell's PATH. Run via 'nix run .#<app>' for this to be set automatically." >&2
  resolve_or_die "$name"
}

# validate_run_name: a run/session name must be a plain path-segment-safe
# token -- rejects anything that could traverse out of $SESSIONS_ROOT
# (e.g. "..", "/", or a leading "-" that a tool might misread as a flag).
validate_run_name() {
  local name="$1"
  if ! [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "error: invalid run name: '$name' (must match ^[A-Za-z0-9._-]+\$)" >&2
    exit 1
  fi
  if [ "$name" = "." ] || [ "$name" = ".." ]; then
    echo "error: invalid run name: '$name'" >&2
    exit 1
  fi
}

# require_run_dir: validates $1 as a run name and prints its (transient,
# /tmp-based -- see SESSIONS_ROOT above) bookkeeping directory on stdout,
# or exits with an error if that directory doesn't exist. NOTE: whether a
# session is actually LIVE is never determined by this directory's
# existence -- only by `nono ps` against nono_state_dir (see below) --
# this is purely for scripts (shell.sh, stop.sh) that need this session's
# own recorded profile.json/shared-paths/workdir-path.
require_run_dir() {
  local name="$1" run_dir
  validate_run_name "$name"
  run_dir="$SESSIONS_ROOT/$name"
  if [ ! -d "$run_dir" ]; then
    echo "error: no run named '$name' found under $SESSIONS_ROOT" >&2
    exit 1
  fi
  printf '%s\n' "$run_dir"
}

# nono_state_dir: prints the single, canonical path for the ONE shared
# nono XDG_STATE_HOME every session in this stack now uses --
# /var/lib/pi/nono-xdg-state on Linux. There is no per-name suffix any
# more (see IMPLEMENTERS.md's "Single nono state dir" section) -- every
# start-agent.sh/shell.sh session, whatever its --name, shares this one
# directory, and `nono ps` against it lists every live session (main and
# "<name>-shell") at once. start-agent.sh is the one authority that wipes
# this dir (only when nothing is live -- see nono_any_session_running),
# and ps.sh/attach.sh/stop.sh/shell.sh must all agree with it exactly, or
# they end up pointed at an empty/wrong XDG_STATE_HOME while the real nono
# session state sits elsewhere (the bug this function exists to prevent).
#
# macOS: the state root must NOT live under /var (== /private/var).
# nono refuses to start when one of the profile's grants overlaps its own
# protected state root ($XDG_STATE_HOME/nono), and the system_read_macos
# group grants read on /private/var as a whole ("Refusing to grant
# '/private/var' ... overlaps protected nono state root"). So on Darwin
# this lives under /Users/Shared by default instead.
# Override the root on either OS with PI_STACK_NONO_STATE_ROOT. `sudo -u
# pi mkdir -p` creates it on first use (/Users/Shared is 1777), and it
# must stay traversable by the invoking user (nono_session_running tests
# -d on it), so don't chmod it to 700.
nono_state_dir() {
  case "$(uname -s)" in
  Darwin) printf '%s\n' "${PI_STACK_NONO_STATE_ROOT:-/Users/Shared/pi-nono-state}" ;;
  *) printf '%s\n' "${PI_STACK_NONO_STATE_ROOT:-/var/lib/pi/nono-xdg-state}" ;;
  esac
}

# nono_state_wipe_preserving_audit STATE_DIR: deletes everything directly
# under STATE_DIR except the `nono` directory itself, then within `nono/`
# deletes everything except `audit` -- net effect: keep only
# STATE_DIR/nono/audit, delete everything else. Shared by start-agent.sh
# (pre-launch wipe, only when no session at all is live -- see
# nono_any_session_running) and stop.sh (post-stop wipe, same "preserve
# audit" rule it always used). A no-op if STATE_DIR doesn't exist; removes
# STATE_DIR outright if it has no nono/audit subtree to preserve.
nono_state_wipe_preserving_audit() {
  local state_dir="${1:?nono_state_wipe_preserving_audit requires a STATE_DIR}"
  sudo -u pi test -d "$state_dir" || return 0
  if sudo -u pi test -d "$state_dir/nono/audit"; then
    sudo -u pi find "$state_dir" -mindepth 1 -maxdepth 1 ! -name nono -exec rm -rf -- {} +
    sudo -u pi find "$state_dir/nono" -mindepth 1 -maxdepth 1 ! -name audit -exec rm -rf -- {} +
  else
    sudo -u pi rm -rf -- "$state_dir"
  fi
}

# nono_any_session_running NONO_BIN STATE_DIR: true (0) if `nono ps`
# against STATE_DIR prints ANY output at all, false otherwise (including
# when STATE_DIR doesn't exist, or the `nono ps` call itself fails). nono
# ps's exact "nothing running" output (empty stdout vs. some fixed
# placeholder line) isn't documented in this checkout -- treating any
# non-empty output as "something's running" is the conservative choice
# here (a false positive just skips a wipe that would have been safe; a
# false negative would wipe out from under a live session).
nono_any_session_running() {
  local nono_bin="$1" state_dir="$2" output
  [ -d "$state_dir" ] || return 1
  output="$(sudo -u pi env XDG_STATE_HOME="$state_dir" "$nono_bin" ps 2>/dev/null)" || return 1
  [ -n "$output" ]
}

# nono_list_live_sessions NONO_BIN STATE_DIR: prints one session name per
# line from `nono ps`'s output, best-effort -- nono ps's exact output
# schema isn't documented in this checkout. Takes the
# first whitespace-delimited field of every non-empty line and keeps only
# tokens that look like a session name (same charset validate_run_name
# accepts, plus the "-shell" suffix this stack appends itself) -- this
# silently (and harmlessly) drops anything that looks like a table header
# instead of a session name/row.
nono_list_live_sessions() {
  local nono_bin="$1" state_dir="$2"
  [ -d "$state_dir" ] || return 0
  sudo -u pi env XDG_STATE_HOME="$state_dir" "$nono_bin" ps 2>/dev/null |
    awk '{print $2}' | grep -E '^[A-Za-z0-9._-]+$' | grep -v "NAME" || true
}

# nono_list_live_main_sessions NONO_BIN STATE_DIR: nono_list_live_sessions,
# minus any "<name>-shell" entries (shell.sh's own session suffix) -- used
# by attach.sh/shell.sh/stop.sh's no-name auto-select (see
# resolve_name_or_auto below).
nono_list_live_main_sessions() {
  local nono_bin="$1" state_dir="$2"
  nono_list_live_sessions "$nono_bin" "$state_dir" | grep -v -- '-shell$' || true
}

# resolve_name_or_auto NAME_ARG NONO_BIN STATE_DIR: if NAME_ARG is
# non-empty, validates and prints it unchanged. Otherwise lists live MAIN
# sessions (nono_list_live_main_sessions) and: exactly one -> prints it;
# zero or several -> prints nothing and returns non-zero after printing a
# clear, listing error to stderr. Shared by attach.sh/shell.sh/stop.sh so
# <name> can be omitted when exactly one session is live.
resolve_name_or_auto() {
  local name_arg="$1" nono_bin="$2" state_dir="$3"
  if [ -n "$name_arg" ]; then
    validate_run_name "$name_arg"
    printf '%s\n' "$name_arg"
    return 0
  fi
  local -a names=()
  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    names+=("$line")
  done < <(nono_list_live_main_sessions "$nono_bin" "$state_dir")
  case "${#names[@]}" in
  0)
    echo "error: no name given and no live session found -- pass a name explicitly" >&2
    return 1
    ;;
  1)
    printf '%s\n' "${names[0]}"
    return 0
    ;;
  *)
    echo "error: no name given and ${#names[@]} live sessions found (${names[*]}) -- pass a name explicitly" >&2
    return 1
    ;;
  esac
}

# resolve_ca_bundle: prints the fully resolved (realpath, all symlinks
# followed) path of the host's CA bundle -- the sandbox has no default CA
# trust store reachable inside it (no SSL_CERT_FILE/NIX_SSL_CERT_FILE/
# NODE_EXTRA_CA_CERTS survive the profile's environment.allow_vars
# stripping, and the usual system bundle path lives behind a symlink chain
# into /nix/store that isn't covered by the sandbox's read grants on its
# own -- see IMPLEMENTERS.md's "CA trust-store handling" note). Tries, in
# order:
#   1. $PI_STACK_CA_BUNDLE (explicit override)
#   2. the caller's $NIX_SSL_CERT_FILE, then $SSL_CERT_FILE (preserves any
#      custom-CA setup already in effect, e.g. from
#      system-tasks-add-trust-certs)
#   3. /etc/ssl/certs/ca-certificates.crt (NixOS / Debian-likes)
#   4. /etc/pki/tls/certs/ca-bundle.crt
#   5. /etc/ssl/cert.pem (macOS)
# Fails loudly if none of these exist, or (unless $1 is the literal string
# "dry-run") if the resolved file isn't readable by the `pi` user --
# checked via `sudo -u pi test -r <path>`, skipped entirely in dry-run
# mode since --dry-run callers must not shell out to sudo.
resolve_ca_bundle() {
  local mode="${1:-}" candidate resolved
  for candidate in \
    "${PI_STACK_CA_BUNDLE:-}" \
    "${NIX_SSL_CERT_FILE:-}" \
    "${SSL_CERT_FILE:-}" \
    "/etc/ssl/certs/ca-certificates.crt" \
    "/etc/pki/tls/certs/ca-bundle.crt" \
    "/etc/ssl/cert.pem"; do
    [ -n "$candidate" ] || continue
    [ -f "$candidate" ] || continue
    resolved="$(realpath "$candidate")"
    if [ "$mode" != "dry-run" ]; then
      if ! sudo -u pi test -r "$resolved"; then
        echo "error: resolved CA bundle $resolved is not readable by the 'pi' user" >&2
        exit 1
      fi
    fi
    printf '%s\n' "$resolved"
    return 0
  done
  echo "error: no CA bundle found (checked \$PI_STACK_CA_BUNDLE, \$NIX_SSL_CERT_FILE, \$SSL_CERT_FILE, /etc/ssl/certs/ca-certificates.crt, /etc/pki/tls/certs/ca-bundle.crt, /etc/ssl/cert.pem) -- set PI_STACK_CA_BUNDLE explicitly to the bundle you want granted." >&2
  exit 1
}

# resolve_shell_env_grants: prints, one per line, the real (symlink-
# resolved) paths that need to be `--add`ed so a sandboxed shell can read
# the host's own shell-environment setup (PATH/env setup normally done by
# a login shell -- see start-agent.sh's/shell.sh's own callers). Resolved
# at launch time rather than hardcoded, since nix-darwin lays /etc/profile
# and /etc/bashrc as symlinks (via /etc/static) into content-addressed
# /nix/store paths (e.g. a `...-etc-profile` derivation) that churn on
# every `update` -- a hardcoded store path breaks silently the next time
# nixpkgs is bumped.
#
# For each of /etc/profile and /etc/bashrc that exists:
#   1. Grants the file's own fully-resolved realpath (its /etc/static ->
#      /nix/store target on nix-darwin; just itself on a plain Linux
#      distro that doesn't symlink it into the store at all).
#   2. Best-effort scans its contents for `. <path>`/`source <path>`
#      lines naming another file that actually exists (nix-darwin's
#      generated profile/bashrc source a separate, sibling
#      `...-set-environment` store path this way for early PATH setup),
#      and grants THAT file's realpath too. This is a plain grep, not a
#      shell parse -- it can miss an unusual sourcing style, but never
#      grants a path that doesn't exist.
# Prints nothing (not an error) if neither file exists. Callers are
# expected to dedupe the combined output themselves (e.g. `awk
# '!seen[$0]++'`, the same order-preserving dedupe gen-profile.sh uses).
resolve_shell_env_grants() {
  local f real sourced_path
  for f in /etc/profile /etc/bashrc; do
    [ -e "$f" ] || continue
    real="$(realpath -e "$f" 2>/dev/null)" || continue
    printf '%s\n' "$real"
    while IFS= read -r sourced_path; do
      [ -n "$sourced_path" ] || continue
      [ -e "$sourced_path" ] || continue
      realpath -e "$sourced_path" 2>/dev/null
    done < <(grep -oE '(^|[^#[:alnum:]_])(\.|source)[[:space:]]+[^[:space:]"'"'"';]+' "$f" 2>/dev/null | awk '{print $NF}')
  done
}

# nono_session_running: returns success (0) if a nono session named $3
# appears to be running against the XDG_STATE_HOME at $2 (queried via
# `nono ps`, run as the `pi` user), failure (1) otherwise. Shared by
# shell.sh's "one shell per run" refusal and stop.sh's refusal to tear
# down a run's state while its shell session is still open -- see both
# scripts and IMPLEMENTERS.md's "scripts/shell.sh" section.
#
# If the state directory doesn't exist at all, there is nothing to query
# -- treated as "not running" without ever invoking nono (same shortcut
# ps.sh already takes for a run with no nono state dir yet).
#
# Does a plain substring grep for the session name against the whole
# `nono ps` output (same approach start-agent.sh's supervisor.sh
# detached-mode poll loop uses), which could in principle false-positive
# against an unrelated session name that happens to contain this one as a
# substring (e.g. "<name>-shell" vs. "<name>-shell-2") -- no narrower
# matching is available without parsing nono ps's output structurally.
nono_session_running() {
  local nono_bin="$1" state_dir="$2" session_name="$3"
  [ -d "$state_dir" ] || return 1
  sudo -u pi env XDG_STATE_HOME="$state_dir" "$nono_bin" ps 2>/dev/null | grep -q "$session_name"
}

# --- Live file sharing (start-agent.sh --add/--clone/workdir, shell.sh) ---
#
# The invoking user's workdir and every --add/--clone extra are shared
# LIVE, read-write, at their real host path, via POSIX ACLs on Linux
# (`setfacl`) or NFSv4-style ACLs on macOS (`chmod +a`), plus a
# traverse-only grant on parent directories where `pi` would otherwise be
# unable to reach the shared path at all -- see share_ensure_parent_traverse
# for the exact, ownership-gated rule (never sudo, never a parent not owned
# by the invoking user). Shared by start-agent.sh and shell.sh; stop.sh
# and both scripts' teardown paths call share_release to reverse it.

# share_stat_uid PATH: prints PATH's owning uid, Linux (`stat -c`) or
# macOS (`stat -f`) flavoured, whichever works.
share_stat_uid() {
  local path="$1"
  stat -c '%u' "$path" 2>/dev/null || stat -f '%u' "$path" 2>/dev/null
}

# share_path_check PATH: resolves PATH to a realpath and refuses to
# share it if it doesn't exist, resolves to "/", resolves to the
# invoking user's own $HOME, or isn't owned by the invoking user.
# Prints the resolved path on stdout on success. Callers must run this
# for EVERY path up front, before granting anything, so a late refusal
# never leaves a partial set of grants behind.
share_path_check() {
  local raw="${1:?share_path_check requires a PATH}"
  local resolved home_resolved owner_uid my_uid
  if [ ! -e "$raw" ]; then
    echo "error: path does not exist: $raw" >&2
    exit 1
  fi
  resolved="$(realpath "$raw")"
  if [ "$resolved" = "/" ]; then
    echo "error: refusing to share '/' -- pick a narrower path" >&2
    exit 1
  fi
  home_resolved="$(realpath "$HOME" 2>/dev/null || printf '%s' "$HOME")"
  if [ "$resolved" = "$home_resolved" ]; then
    echo "error: refusing to share your entire \$HOME ($HOME) -- pick a narrower path" >&2
    exit 1
  fi
  owner_uid="$(share_stat_uid "$resolved")"
  my_uid="$(id -u)"
  if [ -z "$owner_uid" ]; then
    echo "error: could not stat $resolved to check its owner" >&2
    exit 1
  fi
  if [ "$owner_uid" != "$my_uid" ]; then
    echo "error: refusing to share $resolved -- not owned by you (uid $my_uid)" >&2
    exit 1
  fi
  printf '%s\n' "$resolved"
}

# share_ensure_parent_traverse PATH: grants `pi` bare traverse (x/
# search) access on every parent directory of PATH up to (excluding)
# "/", but ONLY where it's actually needed and actually ours to grant:
#   - if `pi` can already traverse a parent (e.g. a world-traversable
#     /home at 755), it's left completely untouched -- no entry added.
#   - else, if the parent is owned by the invoking user, a traverse
#     entry is added (Linux: `setfacl -m u:pi:x`; macOS: `chmod +a
#     "user:pi allow search"`).
#   - else (pi can't traverse it AND the invoking user doesn't own it,
#     e.g. a root-owned /home at 750), this fails loudly with a clear
#     error instead of ever escalating with sudo -- the invoking user
#     cannot grant access to a directory they don't own, and `pi`
#     running as a shared system user must not depend on root-owned
#     system directories being made writable/ACL-able by whoever
#     happens to be sharing a path. The fix in that case is for the
#     directory's actual owner to widen it (e.g. chmod o+x) or for the
#     caller to share a path that doesn't sit under it.
# Computes the FULL list of parents that need a NEW entry before
# touching anything, and returns non-zero before any modification at
# all if any of them isn't owned by the invoking user -- so a failure
# on a high parent never leaves a lower parent (which would have been
# fine on its own) half-modified. Idempotent: a parent that already has
# the entry from a previous call (or already lets `pi` traverse it some
# other way) is simply skipped again.
share_ensure_parent_traverse() {
  local path="${1:?share_ensure_parent_traverse requires a PATH}"
  local my_uid parent owner_uid
  my_uid="$(id -u)"
  local -a needs_grant=()
  parent="$path"
  while true; do
    parent="$(dirname "$parent")"
    [ "$parent" = "/" ] && break
    if sudo -u pi test -x "$parent" 2>/dev/null; then
      continue
    fi
    owner_uid="$(share_stat_uid "$parent")"
    if [ -z "$owner_uid" ]; then
      echo "error: share_ensure_parent_traverse: could not stat $parent to check its owner" >&2
      return 1
    fi
    if [ "$owner_uid" != "$my_uid" ]; then
      echo "error: user pi cannot traverse $parent and you do not own it, so it cannot be granted; fix its permissions (e.g. chmod o+x or an ACL as its owner) or share a path elsewhere" >&2
      return 1
    fi
    needs_grant+=("$parent")
  done

  for parent in "${needs_grant[@]:-}"; do
    [ -n "$parent" ] || continue
    case "$(uname -s)" in
    Linux)
      setfacl -m "u:pi:x" "$parent"
      ;;
    Darwin)
      /bin/chmod -a "user:pi allow search" "$parent" 2>/dev/null || true
      /bin/chmod +a "user:pi allow search" "$parent"
      ;;
    *)
      echo "error: share_ensure_parent_traverse: unsupported OS: $(uname -s)" >&2
      return 1
      ;;
    esac
  done
}

# share_darwin_acl OP PATH USER: macOS-only. OP is "+a" (add) or "-a"
# (remove). Applies ACL entries for USER to PATH, split by type because
# macOS rejects inheritance flags (file_inherit/directory_inherit) on
# regular files with "Invalid argument", and directory-only permission
# names don't belong on files.
#   - regular files: one plain entry.
#   - directories: one entry for the directory itself + subdirectories
#     (directory_inherit), and a SEPARATE only_inherit entry that new
#     files pick up (file_inherit). Two entries because a file inherits
#     the whole entry it matches: with a single combined entry, `search`
#     (== `execute`) would land on every new file.
# The INVOKING user's file entries deliberately omit `execute`: ACLs are
# honoured by access(2), so an `allow execute` on every file makes tools
# that test os.access(path, X_OK) -- e.g. pre-commit's identify /
# check-executables-have-shebangs -- see every file as executable even
# though `ls -l` shows no x bits. Only `pi` gets execute on files.
# `find -type d/-type f` skips symlinks, so chmod never follows a link out
# of the shared tree; `{} +` batches the calls so large trees (.git,
# node_modules) stay fast. Uses /bin/chmod explicitly: under `nix run`
# GNU coreutils' chmod is first on PATH, and it has no ACL support
# ("invalid mode: '+a'").
share_darwin_acl() {
  local op="$1" path="$2" acl_user="$3"
  local base="delete,readattr,writeattr,readextattr,writeextattr,readsecurity"
  local file_exec=""
  [ "$acl_user" = "pi" ] && file_exec=",execute"
  local file_perms="read,write,append${file_exec},$base"
  local dir_perms="list,search,add_file,add_subdirectory,delete_child,$base"
  if [ -d "$path" ]; then
    find "$path" -type d -exec /bin/chmod "$op" "user:$acl_user allow $dir_perms,directory_inherit" {} +
    find "$path" -type d -exec /bin/chmod "$op" "user:$acl_user allow $file_perms,file_inherit,only_inherit" {} +
    find "$path" -type f -exec /bin/chmod "$op" "user:$acl_user allow $file_perms" {} +
  else
    /bin/chmod "$op" "user:$acl_user allow $file_perms" "$path"
  fi
}

# share_grant PATH: grants the `pi` user (and, on directories, a
# default/inherited entry for both `pi` and the invoking user) live
# read-write-execute access to PATH at its real host location, plus
# (via share_ensure_parent_traverse) bare traverse (x/search) access on
# every parent directory of PATH up to (excluding) "/" so `pi` can
# actually reach it -- but ONLY on parents that actually need it and
# are owned by the invoking user; see share_ensure_parent_traverse's
# own comment for the exact rule and why this never escalates with
# sudo. Idempotent: safe to call again on an already-granted PATH.
# Assumes PATH has already been through share_path_check -- this
# function does not re-check it.
share_grant() {
  local path="${1:?share_grant requires a PATH}"
  local invoking_user
  invoking_user="$(id -un)"
  case "$(uname -s)" in
  Linux)
    setfacl -R -m "u:pi:rwX" "$path"
    if [ -d "$path" ]; then
      # `d:` (default) entries only apply to directories -- setfacl
      # errors if asked to set one on a plain file, hence the -type d
      # filter here rather than a single blanket -R call.
      find "$path" -type d -exec setfacl -m "d:u:pi:rwX" {} +
      find "$path" -type d -exec setfacl -m "d:u:${invoking_user}:rwX" {} +
    fi
    ;;
  Darwin)
    # `-a` before `+a` on each entry keeps this idempotent (best effort)
    # rather than accumulating duplicate ACEs on repeated launches.
    # See share_darwin_acl for why directories and files get different
    # entries.
    local acl_user
    for acl_user in pi "$invoking_user"; do
      share_darwin_acl -a "$path" "$acl_user" 2>/dev/null || true
      share_darwin_acl +a "$path" "$acl_user"
    done
    ;;
  *)
    echo "error: share_grant: unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
  esac
  share_ensure_parent_traverse "$path"
}

# share_file_lists_path FILE PATH: true (0) if FILE (one realpath per
# line) contains PATH itself, a parent of PATH, or a child of PATH.
share_file_lists_path() {
  local file="$1" path="$2" line
  [ -f "$file" ] || return 1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$path" in
    "$line" | "$line"/*) return 0 ;;
    esac
    case "$line" in
    "$path"/*) return 0 ;;
    esac
  done <"$file"
  return 1
}

# share_release_blocked PATH SELF_RUN TREAT_SELF_MAIN_LIVE: true (0) if
# some OTHER run (not SELF_RUN) has a live session (its main "<run>" or
# its "<run>-shell") that lists PATH (or a parent/child of it) in its
# own shared-paths file, OR (when TREAT_SELF_MAIN_LIVE=1) SELF_RUN's own
# main "<name>" session is itself still live and lists it.
share_release_blocked() {
  local path="$1" self_run="$2" treat_self_main_live="$3"
  local nono_bin run_dir run_name state_dir shared_file is_live
  nono_bin="$(resolve_stack_bin PI_STACK_NONO_BIN nono)"
  # All sessions now share ONE nono XDG_STATE_HOME (see nono_state_dir) --
  # computed once here rather than per-iteration, unlike the old
  # per-run nono_state_dir_for(run_name).
  state_dir="$(nono_state_dir)"
  for run_dir in "$SESSIONS_ROOT"/*/; do
    [ -d "$run_dir" ] || continue
    run_name="$(basename "$run_dir")"
    shared_file="${run_dir%/}/shared-paths"
    sudo -u pi test -f "$shared_file" || continue
    # Process substitution (not a temp file) -- `pi` owns $shared_file,
    # so reading it still has to run as `pi`, but there's nothing left
    # here for shellcheck to flag about reading/writing the same file.
    if ! share_file_lists_path <(sudo -u pi cat "$shared_file" 2>/dev/null) "$path"; then
      continue
    fi
    if [ "$run_name" = "$self_run" ]; then
      is_live=0
      [ "$treat_self_main_live" = "1" ] && nono_session_running "$nono_bin" "$state_dir" "$run_name" && is_live=1
      [ "$is_live" = "1" ] && return 0
      continue
    fi
    if nono_session_running "$nono_bin" "$state_dir" "$run_name" || nono_session_running "$nono_bin" "$state_dir" "${run_name}-shell"; then
      return 0
    fi
  done
  return 1
}

# share_parent_still_needed PARENT SELF_RUN TREAT_SELF_MAIN_LIVE: true
# (0) if some live run's own recorded share lies under PARENT, so
# PARENT's traverse (x/search) entry is still needed by that other
# share and must not be removed. Same liveness rule as
# share_release_blocked (SELF_RUN is only considered live for this
# purpose when TREAT_SELF_MAIN_LIVE=1, via its main session).
share_parent_still_needed() {
  local parent="$1" self_run="$2" treat_self_main_live="$3"
  local nono_bin run_dir run_name state_dir shared_file line is_live
  nono_bin="$(resolve_stack_bin PI_STACK_NONO_BIN nono)"
  # All sessions now share ONE nono XDG_STATE_HOME -- see
  # share_release_blocked's identical comment above.
  state_dir="$(nono_state_dir)"
  for run_dir in "$SESSIONS_ROOT"/*/; do
    [ -d "$run_dir" ] || continue
    run_name="$(basename "$run_dir")"
    shared_file="${run_dir%/}/shared-paths"
    sudo -u pi test -f "$shared_file" || continue
    is_live=0
    if [ "$run_name" = "$self_run" ]; then
      [ "$treat_self_main_live" = "1" ] && nono_session_running "$nono_bin" "$state_dir" "$run_name" && is_live=1
    else
      if nono_session_running "$nono_bin" "$state_dir" "$run_name" || nono_session_running "$nono_bin" "$state_dir" "${run_name}-shell"; then
        is_live=1
      fi
    fi
    [ "$is_live" = "1" ] || continue
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      case "$line" in
      "$parent"/*)
        return 0
        ;;
      esac
    done < <(sudo -u pi cat "$shared_file" 2>/dev/null)
  done
  return 1
}

# share_release PATH [--self-run NAME] [--treat-self-main-live]
#                [--noninteractive]
# Reverses share_grant: normalizes ownership of anything `pi` left
# behind under PATH back to the invoking user (interactive `sudo` by
# default; --noninteractive uses `sudo -n` and returns non-zero with a
# clear message instead of ever prompting), then removes the ACL
# entries share_grant added -- on PATH itself, and on each parent
# directory where no other live run's own share still needs it (see
# share_parent_still_needed) AND that parent is owned by the invoking
# user -- share_grant (via share_ensure_parent_traverse) never added an
# entry on a parent it didn't own, so a not-owned parent is skipped
# silently here too; there is nothing of ours to remove on it, and this
# never escalates with sudo to attempt one anyway. Skips PATH entirely
# (logging why, as a no-op success) if share_release_blocked says some
# other live run (or, with --treat-self-main-live, NAME's own main
# session) still needs it. Idempotent and tolerant of already-removed
# entries -- every ACL removal here is best-effort.
share_release() {
  local path="${1:?share_release requires a PATH}"
  shift
  local self_run="" treat_self_main_live=0 noninteractive=0
  while [ $# -gt 0 ]; do
    case "$1" in
    --self-run)
      self_run="${2:?--self-run requires a NAME}"
      shift 2
      ;;
    --treat-self-main-live)
      treat_self_main_live=1
      shift
      ;;
    --noninteractive)
      noninteractive=1
      shift
      ;;
    *)
      echo "error: share_release: unknown argument: $1" >&2
      exit 1
      ;;
    esac
  done

  if share_release_blocked "$path" "$self_run" "$treat_self_main_live"; then
    echo "==> share_release: skipping $path -- still shared by another live run" >&2
    return 0
  fi

  local invoking_user invoking_group
  invoking_user="$(id -un)"
  invoking_group="$(id -gn)"

  local sudo_prefix=(sudo)
  [ "$noninteractive" = "1" ] && sudo_prefix=(sudo -n)

  if ! "${sudo_prefix[@]}" find "$path" -user pi -exec chown "${invoking_user}:${invoking_group}" {} +; then
    if [ "$noninteractive" = "1" ]; then
      echo "error: share_release: could not normalize ownership of $path without an interactive sudo prompt -- run 'nix run .#stop -- <name>' to finish restoring ownership/ACLs." >&2
    else
      echo "error: share_release: failed to normalize ownership of $path." >&2
    fi
    return 1
  fi

  case "$(uname -s)" in
  Linux)
    setfacl -R -x u:pi "$path" 2>/dev/null || true
    if [ -d "$path" ]; then
      find "$path" -type d -exec setfacl -x "d:u:pi" {} + 2>/dev/null || true
      find "$path" -type d -exec setfacl -x "d:u:${invoking_user}" {} + 2>/dev/null || true
    fi
    ;;
  Darwin)
    local acl_user
    for acl_user in pi "$invoking_user"; do
      share_darwin_acl -a "$path" "$acl_user" 2>/dev/null || true
    done
    ;;
  esac

  local parent parent_owner_uid my_uid
  my_uid="$(id -u)"
  parent="$path"
  while true; do
    parent="$(dirname "$parent")"
    [ "$parent" = "/" ] && break
    if share_parent_still_needed "$parent" "$self_run" "$treat_self_main_live"; then
      continue
    fi
    # share_grant only ever added an entry on a parent owned by the
    # invoking user (see share_ensure_parent_traverse) -- a parent not
    # owned by them either never got an entry at all, or `pi` could
    # already traverse it some other way, so there's nothing of ours to
    # remove. Skip silently rather than attempting (and best-effort
    # swallowing a failure on) a removal that was never ours to make.
    parent_owner_uid="$(share_stat_uid "$parent")"
    [ "$parent_owner_uid" = "$my_uid" ] || continue
    case "$(uname -s)" in
    Linux) setfacl -x u:pi "$parent" 2>/dev/null || true ;;
    Darwin) /bin/chmod -a "user:pi allow search" "$parent" 2>/dev/null || true ;;
    esac
  done
}

# --- RUN_DIR/shared-paths and RUN_DIR/workdir-path bookkeeping --------
# Both files live inside the pi-owned per-run directory (RUN_DIR itself
# is created `sudo -u pi mkdir -p ...` by start-agent.sh), so every
# read/write here goes through `sudo -u pi`, same as profile.json
# elsewhere in this stack.

# share_record_paths RUN_DIR PATH...: appends every PATH (deduped,
# order-preserving, one realpath per line) to RUN_DIR/shared-paths.
# Used by start-agent.sh (recording workdir + every --add/--clone extra)
# and shell.sh (recording whatever it granted on start, which today is
# just the already-recorded set it re-grants).
share_record_paths() {
  local run_dir="$1"
  shift
  local existing tmp
  tmp="$(mktemp)"
  existing="$(sudo -u pi cat "$run_dir/shared-paths" 2>/dev/null || true)"
  {
    [ -n "$existing" ] && printf '%s\n' "$existing"
    local p
    for p in "$@"; do printf '%s\n' "$p"; done
  } | awk '!seen[$0]++' >"$tmp"
  # shellcheck disable=SC2024 # intentional, same idiom as write_as_pi
  # above: $tmp is already readable by the invoking user (no sudo
  # needed to open it for reading), only `tee`'s write to the pi-owned
  # destination runs as `pi`.
  sudo -u pi tee "$run_dir/shared-paths" <"$tmp" >/dev/null
  rm -f "$tmp"
}

# share_read_paths RUN_DIR: prints every path recorded in
# RUN_DIR/shared-paths, one per line (nothing at all if the file
# doesn't exist yet).
share_read_paths() {
  local run_dir="$1"
  sudo -u pi cat "$run_dir/shared-paths" 2>/dev/null || true
}

# share_write_workdir_path RUN_DIR PATH: records RUN_DIR's live-shared
# workdir path (written as `pi`, same as shared-paths).
share_write_workdir_path() {
  local run_dir="$1" path="$2"
  printf '%s\n' "$path" | sudo -u pi tee "$run_dir/workdir-path" >/dev/null
}

# share_read_workdir_path RUN_DIR: prints RUN_DIR's recorded workdir
# path (empty if none has been recorded -- callers must treat that as
# an error, not a default).
share_read_workdir_path() {
  local run_dir="$1"
  sudo -u pi cat "$run_dir/workdir-path" 2>/dev/null || true
}

# --- git safe.directory plumbing ---------------------------------------
# `pi` and the invoking user are different uids sharing the same live
# path, which trips git's ownership mismatch guard ("detected dubious
# ownership") on the `pi` side (the path is owned by the invoking user,
# not `pi`) -- `safe.directory` entries fed in via GIT_CONFIG_* env vars
# (never a written .gitconfig, which would need its own grant/ownership
# story) sidestep that without editing either user's actual git config.

# git_safe_dir_env PATH...: exports GIT_CONFIG_COUNT plus one
# GIT_CONFIG_KEY_i=safe.directory / GIT_CONFIG_VALUE_i=<path> pair per
# PATH, starting AFTER any GIT_CONFIG_COUNT already exported on this
# process (so repeated/combined calls never clobber each other), and
# exposes every var name it just exported (including GIT_CONFIG_COUNT
# itself) via the global array GIT_SAFE_DIR_ENV_VARS, so callers can fold
# them into a `sudo --preserve-env=...` list.
GIT_SAFE_DIR_ENV_VARS=()
git_safe_dir_env() {
  local start_count="${GIT_CONFIG_COUNT:-0}" i=0 idx path
  GIT_SAFE_DIR_ENV_VARS=()
  for path in "$@"; do
    [ -n "$path" ] || continue
    idx=$((start_count + i))
    export "GIT_CONFIG_KEY_${idx}=safe.directory"
    export "GIT_CONFIG_VALUE_${idx}=$path"
    GIT_SAFE_DIR_ENV_VARS+=("GIT_CONFIG_KEY_${idx}" "GIT_CONFIG_VALUE_${idx}")
    i=$((i + 1))
  done
  if [ "$i" -gt 0 ]; then
    export GIT_CONFIG_COUNT=$((start_count + i))
    GIT_SAFE_DIR_ENV_VARS+=("GIT_CONFIG_COUNT")
  fi
}
