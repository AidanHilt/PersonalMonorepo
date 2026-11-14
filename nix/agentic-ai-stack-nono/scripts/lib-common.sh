#!/usr/bin/env bash
# lib-common.sh -- shared helpers for the session-wrapper scripts added in
# Phase 4b of PLAN.md (ps.sh, attach.sh, stop.sh, login.sh). NOT sourced by
# scripts/start-agent.sh itself: that script predates this file (Phase 4a)
# and already carries its own copies of resolve_or_die/resolve_stack_bin --
# left as-is rather than touched here, per the dispatch's out-of-scope
# note.
#
# Must be `source`d (not executed) by a caller that has already run
# `set -euo pipefail` and defines PERSONAL_MONOREPO_LOCATION (same
# convention as start-agent.sh).
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
