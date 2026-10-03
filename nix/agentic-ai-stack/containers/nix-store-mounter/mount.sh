#!/usr/bin/env bash
# containers/nix-store-mounter/mount.sh
#
# Runs inside the `nix-store-mounter` service (compose.nixstore-overlay.yaml),
# which uses the *pi* image, so /nix/store here is exactly pi's own closure --
# nothing from pkg-broker, nothing from the host.
#
# It builds a read-only union of
#     1. this image's own /nix/store                (pi's closure)
#     2. the shared volume's nix/store              (what pkg-broker built)
# onto /srv/merged. /srv/merged is a bind of a host directory with rshared
# propagation, so the mount becomes visible on the host, and `pi` bind-mounts
# the same host directory with rslave (receives the mount, cannot push back).
#
# Needs CAP_SYS_ADMIN and `mount` (util-linux) in the pi image. No network.
set -eu

LOWER_BROKER=/srv/shared-nix/nix/store
TARGET=/srv/merged

echo "nix-store-mounter: waiting for $LOWER_BROKER (created by pkg-broker's entrypoint)..."
until [ -d "$LOWER_BROKER" ]; do sleep 1; done

# First lowerdir wins on conflicts; store paths are hash-addressed, so they
# should never collide.
if ! mount -t overlay -o "lowerdir=/nix/store:${LOWER_BROKER}" overlay "$TARGET"; then
  echo "nix-store-mounter: overlay mount failed. Likely causes:" >&2
  echo "  - AppArmor/seccomp blocking mount(2) (needs apparmor:unconfined + SYS_ADMIN)" >&2
  echo "  - 'mount' missing from the pi image (add pkgs.util-linux)" >&2
  echo "  - kernel refusing an overlay-on-overlay lowerdir (see dmesg)" >&2
  exit 1
fi

if [ -z "$(ls -A "$TARGET" 2>/dev/null)" ]; then
  echo "nix-store-mounter: $TARGET is empty after mounting, refusing to report ready." >&2
  umount "$TARGET" || true
  exit 1
fi

# Unmount on shutdown; the umount propagates to the host through the shared
# bind, so no mount is left behind. `docker compose down` sends SIGTERM.
trap 'echo "nix-store-mounter: unmounting $TARGET"; umount "$TARGET" || true; rm -f /tmp/ready; exit 0' TERM INT

touch /tmp/ready
echo "nix-store-mounter: $TARGET ready."
while :; do
  sleep 1 &
  wait $! || true
done