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
  # In this mode the host's real /nix is mounted at /nix in this container
  # too, so logical store paths (/nix/store/...) ARE their own physical
  # location -- no chroot-store translation needed.
  export PKG_BROKER_STORE_READ_ROOT="/"

  # Unlike isolated mode (below), do NOT copy the pinned nixpkgs tree here:
  # that copy exists only to work around chroot-store evaluation of
  # store-path sources (see isolated mode's comment below), and host-store
  # mode isn't a chroot store. Instead, point straight at the baked symlink
  # /etc/pkg-broker/nixpkgs -> pkgs.path, resolved through the host's real
  # /nix/store (now bind-mounted at /nix, replacing the image's own store
  # view). This only resolves if the image was built on this same host --
  # pkgs.path's target must already exist in the host's /nix/store, since
  # the bind mount hides whatever the image itself shipped with. See
  # containers/pkg-broker/README.md's host-store section.
  export PKG_BROKER_NIXPKGS_PATH="/etc/pkg-broker/nixpkgs"

  # Fail fast, loudly, before accepting any /resolve traffic, if either
  # prerequisite for host-store mode isn't actually met, rather than
  # surfacing a cryptic nix-build failure on the first real request.
  if [ ! -e "$PKG_BROKER_NIXPKGS_PATH/default.nix" ]; then
    echo "pkg-broker-entrypoint: $PKG_BROKER_NIXPKGS_PATH/default.nix does not exist." >&2
    echo "  host-store mode requires this image to have been built on THIS SAME host:" >&2
    echo "  the host's real /nix/store is bind-mounted over the image's own store," >&2
    echo "  hiding whatever pkgs.path pointed at inside the image. If the image was" >&2
    echo "  built elsewhere (or the host store was since garbage-collected), that" >&2
    echo "  path is simply not present here. Rebuild/push the image on this host," >&2
    echo "  or fall back to the default (non-host-store) backend." >&2
    exit 1
  fi
  if [ ! -S /nix/var/nix/daemon-socket/socket ]; then
    echo "pkg-broker-entrypoint: /nix/var/nix/daemon-socket/socket does not exist." >&2
    echo "  host-store mode requires the host's nix-daemon socket to be bind-mounted" >&2
    echo "  in (see compose.pkgbroker-host-store.yaml) -- without it, NIX_REMOTE=daemon" >&2
    echo "  has nothing to talk to." >&2
    exit 1
  fi

  exec "$SERVER" "$@"
fi

ROOT="${PKG_BROKER_STORE_ROOT:-/srv/shared-nix}"

if [ ! -d "$ROOT" ] || [ ! -w "$ROOT" ]; then
  echo "pkg-broker-entrypoint: $ROOT is missing or not writable by uid $(id -u)." >&2
  echo "  actual owner/mode: $(ls -ldn "$ROOT" 2>&1)" >&2
  echo "  expected: uid/gid 10003, mode drwxr-xr-x (seeded from the image on first volume creation)." >&2
  echo "  Fix: docker compose down; docker volume rm agentic-ai-stack_nix-store; then start again (after rebuilding the broker image)." >&2
  exit 1
fi

# 0755 because pi reads this tree as a different uid (10001).
mkdir -p "$ROOT/nix/store" "$ROOT/nix/var/nix"
chmod 0755 "$ROOT/nix" "$ROOT/nix/store"

export NIX_REMOTE="local?root=$ROOT"

# nix-build reports LOGICAL store paths (/nix/store/...), but inside a
# chroot store those paths are physically on disk at $ROOT/nix/store/...
# ($ROOT, not /nix/store) -- the broker's own /nix/store is the image's
# store, unrelated to the chroot store's contents. The server needs the
# physical root to actually read bin/ dirs off disk; symlink targets it
# publishes still use the logical path (resolved via pi's overlay/bind, not
# this process's filesystem view).
export PKG_BROKER_STORE_READ_ROOT="$ROOT"

# Isolated mode only (host-store mode returns above, before this point, and
# uses /etc/pkg-broker/nixpkgs directly -- see its branch's comment).
# Evaluation inside a chroot store resolves store-dir paths relative to the
# chroot, so a nixpkgs path that points into the broker image's /nix/store
# will not be found. Keep the pinned nixpkgs tree at a plain, non-store path
# instead. (Same pinned source tree: /etc/pkg-broker/nixpkgs -> pkgs.path.)
# If nix-build turns out to evaluate the symlink fine, this block can go.
SRC=/srv/pkg-broker/nixpkgs
if [ ! -e "$SRC/.copied" ]; then
  echo "pkg-broker-entrypoint: copying pinned nixpkgs to $SRC (first start only)..." >&2
  # Preserve file MODES (only drop ownership): Nix hashes a source path's
  # file modes (executable bit included) when it imports a ./path
  # expression, so stripping modes changes the computed store path and
  # every derivation downstream of it stops matching cache.nixos.org --
  # silently falling back to a full from-source rebuild starting at
  # bootstrap-stage0. Ownership still needs dropping because the source
  # tree is a read-only store path owned by root/the build user, not
  # uid 10003; `chmod -R u+w` below makes the copy writable for that uid.
  cp -r --no-preserve=ownership /etc/pkg-broker/nixpkgs/. "$SRC/"
  chmod -R u+w "$SRC"
  touch "$SRC/.copied"
fi
export PKG_BROKER_NIXPKGS_PATH="$SRC"

# Opens (and on first run creates) the chroot store's database, so a broken
# store fails here, loudly, instead of on the first /resolve request.
nix-store --store "$NIX_REMOTE" --dump-db >/dev/null

# Sandbox self-test: nix.conf now requires sandbox = true (see nix.conf's
# header comment for why a chroot store needs the sandbox), which needs
# user namespaces + mount + a mountable /proc -- all opt-outs granted via
# compose.yaml's pkg-broker `security_opt` list, not ambient container
# privilege. Fail fast, loudly, before accepting any /resolve traffic, if
# that didn't actually work, rather than surfacing a cryptic build failure
# on the first real request. The derivation name is salted with the
# current time so this is a real build every start, not a cached no-op.
if ! err=$(nix-build --no-out-link --store "$NIX_REMOTE" \
  --argstr salt "pkg-broker-sandbox-check-$(date +%s%N)" \
  -E '{ salt }: derivation { name = salt; system = builtins.currentSystem; builder = "/bin/sh"; args = [ "-c" "echo ok > $out" ]; }' \
  2>&1); then
  echo "$err"
  echo "pkg-broker-entrypoint: sandboxed test build failed -- refusing to start." >&2
  echo "  nix-build output:" >&2
  while IFS= read -r line; do echo "    $line" >&2; done <<< "$err"
  echo "  nix.conf requires sandbox = true (needed for the chroot store, see nix.conf)." >&2
  echo "  Likely causes:" >&2
  echo "    - compose.yaml's pkg-broker service is missing one of the required" >&2
  echo "      security_opt entries: seccomp:unconfined, apparmor:unconfined," >&2
  echo "      systempaths=unconfined." >&2
  echo "    - the host kernel has unprivileged user namespaces disabled or" >&2
  echo "      restricted (e.g. Ubuntu's kernel.apparmor_restrict_unprivileged_userns=1)" >&2
  echo "      -- see containers/pkg-broker/README.md." >&2
  exit 1
fi

echo "pkg-broker-entrypoint: store ready (NIX_REMOTE=$NIX_REMOTE), starting $SERVER" >&2
exec "$SERVER" "$@"