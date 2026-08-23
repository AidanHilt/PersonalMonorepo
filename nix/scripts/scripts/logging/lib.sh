#!/usr/bin/env bash
# Contract: sourced by run.sh scripts via `# @lib: logging`.
# Exposes log_info(msg) and log_error(msg), both writing to stderr with a level prefix.

log_info() {
  echo "[INFO] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}
