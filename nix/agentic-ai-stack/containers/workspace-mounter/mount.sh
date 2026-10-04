#!/usr/bin/env bash
# containers/workspace-mounter/mount.sh
#
# Runs inside the `workspace-mounter` service (compose.workspace.yaml),
# layered by start-agent.sh only when the user passes one or more
# --add/--clone extras. Publishes a merged /workspace view to the host via
# a shared-propagation bind at $TARGET, mirroring
# containers/nix-store-mounter/mount.sh's approach but using `bindfs` (FUSE)
# instead of an overlay mount: each source needs its host ownership
# translated to pi's uid:gid (10001) for reads, while writes still land on
# the host under the real host uid:gid -- bindfs's --force-user/
# --force-group/--create-for-user/--create-for-group do exactly that,
# regardless of the source's actual host permissions.
#
# Inputs (env, set by start-agent.sh -- see compose.workspace.yaml and the
# per-run generated extras compose file it layers on top of it):
#   WORKSPACE_MODE      "single" or "sibling"
#   WORKSPACE_ITEMS     ordered "name:type,name:type,..." list (type is
#                       "dir" or "file"), one entry per extra, in the same
#                       order the matching source volumes were bind-mounted
#                       at /srv/sources/<name>.
#   WORKSPACE_HOST_UID  host uid of the user running start-agent.sh
#   WORKSPACE_HOST_GID  host gid of the user running start-agent.sh
#
# For a "dir" item, /srv/sources/<name> is a bind of the extra's directory
# itself. For a "file" item, /srv/sources/<name> is a bind of the file's
# PARENT directory (its basename matches <name>'s own basename inside that
# directory) -- bindfs only operates on directories here, and mounting the
# parent (not the file) lets the single translated file be re-exposed on its
# own at $TARGET/<name> without exposing the rest of that parent directory
# through the merged view pi actually gets.
#
# Needs CAP_SYS_ADMIN + /dev/fuse (bindfs) in this image. No network.
set -eu

TARGET=/srv/merged
SOURCES=/srv/sources
INTERNAL=/srv/internal

: "${WORKSPACE_MODE:?WORKSPACE_MODE must be set}"
: "${WORKSPACE_ITEMS:?WORKSPACE_ITEMS must be set}"
: "${WORKSPACE_HOST_UID:?WORKSPACE_HOST_UID must be set}"
: "${WORKSPACE_HOST_GID:?WORKSPACE_HOST_GID must be set}"

mkdir -p "$INTERNAL"

MOUNTED_PATHS=()

cleanup() {
  echo "workspace-mounter: unmounting..."
  # Unmount in reverse order: file binds before the internal bindfs mount
  # they sit on top of, sibling bindfs mounts before the shared target.
  for ((idx = ${#MOUNTED_PATHS[@]} - 1; idx >= 0; idx--)); do
    umount "${MOUNTED_PATHS[$idx]}" 2>/dev/null || true
  done
  umount -l "$TARGET" 2>/dev/null || true
  rm -f /tmp/ready
  exit 0
}
trap cleanup TERM INT

mount_dir_bindfs() {
  src="$1"; dst="$2"
  mkdir -p "$dst"
  bindfs \
    --force-user=10001 --force-group=10001 \
    --create-for-user="$WORKSPACE_HOST_UID" --create-for-group="$WORKSPACE_HOST_GID" \
    "$src" "$dst"
  MOUNTED_PATHS+=("$dst")
}

IFS=',' read -r -a ITEMS <<< "$WORKSPACE_ITEMS"

if [ "$WORKSPACE_MODE" = "single" ]; then
  if [ "${#ITEMS[@]}" -ne 1 ]; then
    echo "workspace-mounter: WORKSPACE_MODE=single requires exactly one item (got ${#ITEMS[@]})" >&2
    exit 1
  fi
  name="${ITEMS[0]%%:*}"
  type="${ITEMS[0]##*:}"
  if [ "$type" != "dir" ]; then
    echo "workspace-mounter: single mode requires a directory item (got '$type' for '$name')" >&2
    exit 1
  fi
  mount_dir_bindfs "$SOURCES/$name" "$TARGET"
else
  mkdir -p "$TARGET"
  for item in "${ITEMS[@]}"; do
    name="${item%%:*}"
    type="${item##*:}"
    case "$type" in
      dir)
        mount_dir_bindfs "$SOURCES/$name" "$TARGET/$name"
        ;;
      file)
        parent_mount="$INTERNAL/$name"
        mount_dir_bindfs "$SOURCES/$name" "$parent_mount"
        touch "$TARGET/$name"
        mount --bind "$parent_mount/$name" "$TARGET/$name"
        MOUNTED_PATHS+=("$TARGET/$name")
        ;;
      *)
        echo "workspace-mounter: unknown item type '$type' for '$name'" >&2
        exit 1
        ;;
    esac
  done
fi

touch /tmp/ready
echo "workspace-mounter: $TARGET ready (mode=$WORKSPACE_MODE, items=$WORKSPACE_ITEMS)."
while :; do
  sleep 1 &
  wait $! || true
done
