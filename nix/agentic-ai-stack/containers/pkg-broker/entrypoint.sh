#!/usr/bin/env bash
# pkg-broker-entrypoint -- prepares the broker's store, then execs the server.
#
# Runs as the unprivileged pkg-broker user (uid 10003) with no added
# capabilities. The broker's OWN closure (nix, bash, the server binary...)
# stays where the image put it, in the image's /nix/store, and is never
# written to the shared volume. The shared volume is used purely as a
# Nix *chroot store* that builds land in:
#
#   logical store dir : /nix/store           (so cache.nixos.org substitutes
#                                              and absolute paths keep working)
#   physical location : $ROOT/nix/store      ($ROOT = the shared volume)
#
# pi never sees the broker's closure, and the broker never sees pi's.
# The nix-store-mounter service (compose.nixstore-overlay.yaml) is what
# unions pi's own image store with $ROOT/nix/store for pi.
set -euo pipefail

SERVER="${PKG_BROKER_SERVER:-/bin/pkg-broker}"

# Host-store mode (compose.pkgbroker-host-store.yaml): the override mounts the
# host's real /nix and provides its own NIX_REMOTE / daemon socket. Nothing to
# set up here. The override must set PKG_BROKER_HOST_STORE=1.
if [ "${PKG_BROKER_HOST_STORE:-0}" = "1" ]; then
  echo "pkg-broker-entrypoint: host-store mode, using the store the compose override provides." >&2
  exec "$SERVER" "$@"
fi

ROOT="${PKG_BROKER_STORE_ROOT:-/srv/shared-nix}"

if [ ! -d "$ROOT" ] || [ ! -w "$ROOT" ]; then
  echo "pkg-broker-entrypoint: $ROOT is missing or not writable by uid $(id -u)." >&2
  echo "  If the nix-store volume predates this layout, remove it: docker volume rm agentic-ai-stack_nix-store" >&2
  exit 1
fi

# 0755 because pi reads this tree as a different uid (10001).
mkdir -p "$ROOT/nix/store" "$ROOT/nix/var/nix"
chmod 0755 "$ROOT/nix" "$ROOT/nix/store"

export NIX_REMOTE="local?root=$ROOT"

# Evaluation inside a chroot store resolves store-dir paths relative to the
# chroot, so a nixpkgs path that points into the broker image's /nix/store
# will not be found. Keep the pinned nixpkgs tree at a plain, non-store path
# instead. (Same pinned source tree: /etc/pkg-broker/nixpkgs -> pkgs.path.)
# If nix-build turns out to evaluate the symlink fine, this block can go.
SRC=/srv/pkg-broker/nixpkgs
if [ ! -e "$SRC/.copied" ]; then
  echo "pkg-broker-entrypoint: copying pinned nixpkgs to $SRC (first start only)..." >&2
  cp -r --no-preserve=mode,ownership /etc/pkg-broker/nixpkgs/. "$SRC/"
  touch "$SRC/.copied"
fi
export PKG_BROKER_NIXPKGS_PATH="$SRC"

# Opens (and on first run creates) the chroot store's database, so a broken
# store fails here, loudly, instead of on the first /resolve request.
nix-store --store "$NIX_REMOTE" --dump-db >/dev/null

echo "pkg-broker-entrypoint: store ready (NIX_REMOTE=$NIX_REMOTE), starting $SERVER" >&2
exec "$SERVER" "$@"