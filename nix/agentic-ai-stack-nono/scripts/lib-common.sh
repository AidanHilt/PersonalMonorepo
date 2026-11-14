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
