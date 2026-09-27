#!/usr/bin/env bash
# Sets up the pi-sandbox auth directory with fixed ownership/perms so
# the `login` container (running as uid:gid 10001:10001) can read and
# write auth.json without any runtime permission juggling.
#
# Destructive on purpose: if the directory already exists with wrong
# ownership or looser perms, this will forcibly correct it rather than
# erroring out. Re-run any time you're unsure of its state.
set -euo pipefail

AUTH_DIR="${PI_AUTH_DIR:-$HOME/.config/pi-sandbox/agent}"
UID_TARGET=10001
GID_TARGET=10001

echo "info: setting up auth dir at $AUTH_DIR (uid:gid ${UID_TARGET}:${GID_TARGET}, mode 0770)" >&2

# compose.yaml bind-mounts these two paths on top of the ~/.pi tmpfs, so
# they must already exist on the host: a missing file source makes Docker
# create a root-owned *directory* in its place, which then breaks the
# uid:10001 container. Create both up front.
mkdir -p "$AUTH_DIR" "$AUTH_DIR/sessions"
touch "$AUTH_DIR/auth.json"

# chown requires root unless you already own it as the target uid —
# so always go through sudo rather than trying to detect and skip.
sudo chown -R "${UID_TARGET}:${GID_TARGET}" "$AUTH_DIR"
sudo chmod -R 0770 "$AUTH_DIR"

echo "info: done. current state:" >&2
sudo ls -la "$AUTH_DIR"
