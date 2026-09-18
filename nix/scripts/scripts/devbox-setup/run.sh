#!/usr/bin/env bash
#
# setup-devbox.sh
#
# Idempotently creates/starts the "devbox" NixOS VM using the prebuilt
# juspay/nixden release image, via `limactl` directly against the release
# asset URL (no curl-to-sh, no local Nix build required).
#
# Usage:
#   setup-devbox.sh
#       Human-invoked. Verbose (stdout). Creates the VM if it doesn't exist,
#       starts it if it's stopped, no-ops if it's already running. Finishes
#       by refreshing the SSH config (calls configure-ssh.sh next to this
#       script, if present).
#
#   setup-devbox.sh --ensure
#       Quiet mode, meant to be called from an SSH ProxyCommand. All
#       messages go to stderr (so stdout stays clean for the SSH data
#       stream), and it does NOT touch the SSH config. Exits 0 once the VM
#       is confirmed running.
#
# Sizing (M1 Pro, 6-core allocation, 16GB host RAM):
#   vCPUs  = 6
#   memory = 12 GiB   (nixden's own "host RAM - 4GiB" heuristic)
#   disk   = 300 GB   (ceiling only; Lima's qcow2 is sparse and grows lazily)
#
# These only take effect the FIRST time the VM is created. To resize later,
# edit the values below and run `just delete` / re-run this script, or use
# `limactl edit devbox`.

set -euo pipefail

VM_NAME="devbox"
VCPUS=6
MEMORY_GIB=12
DISK_GB=300
TEMPLATE_URL="https://github.com/juspay/nixden/releases/latest/download/nixden-lima.yaml"
SCRATCH_DIR="/tmp/lima-nixden" # fixed by the nixden template itself, independent of --name

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE="interactive"
if [[ "${1:-}" == "--ensure" ]]; then
  MODE="ensure"
fi

log() {
  if [[ "$MODE" == "ensure" ]]; then
    echo "$@" >&2
  else
    echo "$@"
  fi
}

if ! command -v limactl >/dev/null 2>&1; then
  echo "limactl not found. Install Lima first: brew install lima" >&2
  exit 1
fi

# nixden's template mounts this fixed path from the host for intentional
# file transfer; it does not track --name. Created here since we're not
# going through the published `start` convenience script that normally
# does this for you.
mkdir -p "$SCRATCH_DIR"

if limactl list "$VM_NAME" >/dev/null 2>&1; then
  status="$(limactl list --format '{{.Status}}' "$VM_NAME" 2>/dev/null || echo Unknown)"
  case "$status" in
  Running)
    log "devbox is already running."
    ;;
  Stopped)
    log "devbox exists but is stopped. Starting it..."
    limactl start "$VM_NAME" >&2
    log "devbox is running."
    ;;
  *)
    log "devbox is in state '$status'. Attempting to start..."
    limactl start "$VM_NAME" >&2
    log "devbox is running."
    ;;
  esac
else
  log "devbox does not exist yet. Creating it from the published nixden image..."
  log "  cpus=${VCPUS} memory=${MEMORY_GIB}GiB disk=${DISK_GB}GB"
  limactl start \
    --name="$VM_NAME" \
    --cpus "$VCPUS" \
    --memory "$MEMORY_GIB" \
    --disk "$DISK_GB" \
    --tty=false \
    "$TEMPLATE_URL" >&2
  log "devbox created and running."
fi

if [[ "$MODE" == "interactive" ]]; then
  if [[ -x "$SCRIPT_DIR/configure-ssh.sh" ]]; then
    log "Refreshing SSH config..."
    "$SCRIPT_DIR/configure-ssh.sh"
  else
    log "Note: configure-ssh.sh not found next to this script; skipping SSH config refresh."
  fi
fi
