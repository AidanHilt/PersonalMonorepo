#!/usr/bin/env bash
# lib-common.sh -- shared helpers for the session-wrapper scripts added in
# Phase 4b of PLAN.md (ps.sh, attach.sh, stop.sh, login.sh, shell.sh), plus
# start-agent.sh itself. start-agent.sh originally predated this file
# (Phase 4a) and kept its own duplicate copies of resolve_or_die/
# resolve_stack_bin/validate_run_name/nono_state_dir_for/resolve_ca_bundle
# by convention -- that convention ended with the live-file-sharing change
# (see IMPLEMENTERS.md's "Live file sharing" section): start-agent.sh now
# sources this file too, and its duplicate copies were removed.
#
# Also provides the live-file-sharing primitives start-agent.sh/shell.sh/
# stop.sh use to share (and later release) the invoking user's workdir and
# every --add/--clone extra LIVE at its real host path, via ACLs, instead
# of copying it into a pi-owned location: share_path_check, share_grant,
# share_release (plus its helpers share_file_lists_path/
# share_release_blocked/share_parent_still_needed), git_safe_dir_env, and
# the RUN_DIR/shared-paths + RUN_DIR/workdir-path bookkeeping helpers
# (share_record_paths/share_read_paths/share_write_workdir_path/
# share_read_workdir_path). See each function's own comment below, and
# IMPLEMENTERS.md's "Live file sharing" section for the full model.
#
# Must be `source`d (not executed) by a caller that has already run
# `set -euo pipefail` and defines PERSONAL_MONOREPO_LOCATION (same
# convention as every script that sources this file).
#
# shellcheck shell=bash

: "${PERSONAL_MONOREPO_LOCATION:?PERSONAL_MONOREPO_LOCATION must point at the monorepo checkout}"
# shellcheck disable=SC2034 # STACK_DIR is used by scripts that `source`
# this file (login.sh, in particular), not by this file itself.
STACK_DIR="$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack-nono"
RUNS_ROOT="/var/lib/pi/runs"

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
# token -- rejects anything that could traverse out of $RUNS_ROOT (e.g.
# "..", "/", or a leading "-" that a tool might misread as a flag).
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

# require_run_dir: validates $1 as a run name and prints its run directory
# on stdout, or exits with an error if that run directory doesn't exist.
require_run_dir() {
  local name="$1" run_dir
  validate_run_name "$name"
  run_dir="$RUNS_ROOT/$name"
  if [ ! -d "$run_dir" ]; then
    echo "error: no run named '$name' found under $RUNS_ROOT" >&2
    exit 1
  fi
  printf '%s\n' "$run_dir"
}

# nono_state_dir_for: validates $1 as a run name and prints the single,
# canonical path for that run's nono XDG_STATE_HOME --
# /var/lib/pi/<name>-nono-xdg-state. This is a SIBLING of $RUNS_ROOT (not
# nested under $RUNS_ROOT/<name>/), per the launcher's own layout --
# start-agent.sh is the one authority for where this lives (its
# NONO_STATE_DIR variable), and ps.sh/attach.sh/stop.sh must all agree
# with it exactly, or `nix run .#ps`/`.#attach`/`.#stop` end up pointed at
# an empty/wrong XDG_STATE_HOME while the real nono session state sits
# elsewhere (the bug this function exists to prevent).
#
# start-agent.sh now sources this file (see this file's header comment
# above), so there is exactly one copy of this function for every
# script in this stack to agree on -- no more need for a "keep two
# copies in sync" note; see IMPLEMENTERS.md's "scripts/lib-common.sh"
# section for the drift bug this used to invite before that.
nono_state_dir_for() {
  local name="$1"
  validate_run_name "$name"
  printf '%s\n' "/var/lib/pi/${name}-nono-xdg-state"
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
# UNVERIFIED: nono ps's exact output format was not confirmed against a
# real nono binary in this environment. Like start-agent.sh's own
# supervisor.sh detached-mode poll loop (`nono ps | grep -q
# "$SESSION_NAME"`, see IMPLEMENTERS.md), this does a plain substring
# grep for the session name against the whole `nono ps` output, which
# could in principle false-positive against an unrelated session name
# that happens to contain this one as a substring (e.g. "<name>-shell"
# vs. "<name>-shell-2") -- no narrower matching was available without a
# real nono binary to check its actual table/column shape against.
nono_session_running() {
  local nono_bin="$1" state_dir="$2" session_name="$3"
  [ -d "$state_dir" ] || return 1
  sudo -u pi env XDG_STATE_HOME="$state_dir" "$nono_bin" ps 2>/dev/null | grep -q "$session_name"
}

# --- Live file sharing (start-agent.sh --add/--clone/workdir, shell.sh) ---
#
# Reverses the earlier copy-only model (PLAN.md's old "Sharing files
# between aidan and pi" decision row): the invoking user's workdir and
# every --add/--clone extra are shared LIVE, read-write, at their real
# host path, via POSIX ACLs on Linux (`setfacl`) or NFSv4-style ACLs on
# macOS (`chmod +a` -- UNVERIFIED, no macOS available in this effort to
# test any of the macOS branches below against). Shared by
# start-agent.sh and shell.sh; stop.sh and both scripts' teardown paths
# call share_release to reverse it.

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

# share_grant PATH: grants the `pi` user (and, on directories, a
# default/inherited entry for both `pi` and the invoking user) live
# read-write-execute access to PATH at its real host location, plus
# bare traverse (x/search) access on every parent directory of PATH up
# to (excluding) "/" so `pi` can actually reach it. Idempotent: safe to
# call again on an already-granted PATH. Assumes PATH has already been
# through share_path_check -- this function does not re-check it.
share_grant() {
  local path="${1:?share_grant requires a PATH}"
  local invoking_user parent
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
    parent="$path"
    while true; do
      parent="$(dirname "$parent")"
      [ "$parent" = "/" ] && break
      setfacl -m "u:pi:x" "$parent"
    done
    ;;
  Darwin)
    # UNVERIFIED: no macOS host was available to test any of this
    # against a real Seatbelt/APFS ACL. `chmod -a` before `+a` on each
    # entry keeps this idempotent (best effort) rather than
    # accumulating duplicate ACEs on repeated launches.
    local perms="read,write,execute,delete,append,readattr,writeattr,readextattr,writeextattr,readsecurity,list,search,add_file,add_subdirectory,delete_child,file_inherit,directory_inherit"
    local acl_user
    for acl_user in pi "$invoking_user"; do
      chmod -R -a "user:$acl_user allow $perms" "$path" 2>/dev/null || true
      chmod -R +a "user:$acl_user allow $perms" "$path"
    done
    parent="$path"
    while true; do
      parent="$(dirname "$parent")"
      [ "$parent" = "/" ] && break
      chmod -a "user:pi allow search" "$parent" 2>/dev/null || true
      chmod +a "user:pi allow search" "$parent"
    done
    ;;
  *)
    echo "error: share_grant: unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
  esac
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
  for run_dir in "$RUNS_ROOT"/*/; do
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
    state_dir="$(nono_state_dir_for "$run_name")"
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
  for run_dir in "$RUNS_ROOT"/*/; do
    [ -d "$run_dir" ] || continue
    run_name="$(basename "$run_dir")"
    shared_file="${run_dir%/}/shared-paths"
    sudo -u pi test -f "$shared_file" || continue
    state_dir="$(nono_state_dir_for "$run_name")"
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
# share_parent_still_needed). Skips PATH entirely (logging why, as a
# no-op success) if share_release_blocked says some other live run (or,
# with --treat-self-main-live, NAME's own main session) still needs it.
# Idempotent and tolerant of already-removed entries -- every ACL
# removal here is best-effort.
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
    # UNVERIFIED, see share_grant's own note.
    local perms="read,write,execute,delete,append,readattr,writeattr,readextattr,writeextattr,readsecurity,list,search,add_file,add_subdirectory,delete_child,file_inherit,directory_inherit"
    local acl_user
    for acl_user in pi "$invoking_user"; do
      chmod -R -a "user:$acl_user allow $perms" "$path" 2>/dev/null || true
    done
    ;;
  esac

  local parent
  parent="$path"
  while true; do
    parent="$(dirname "$parent")"
    [ "$parent" = "/" ] && break
    if share_parent_still_needed "$parent" "$self_run" "$treat_self_main_live"; then
      continue
    fi
    case "$(uname -s)" in
    Linux) setfacl -x u:pi "$parent" 2>/dev/null || true ;;
    Darwin) chmod -a "user:pi allow search" "$parent" 2>/dev/null || true ;;
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
