#!/usr/bin/env bash
# @lib: logging
set -euo pipefail

src="${1:?usage: backup <src> <dest>}"
dest="${2:?usage: backup <src> <dest>}"

log_info "backing up ${src} -> ${dest}"
rsync -a "${src}" "${dest}"
log_info "done"
