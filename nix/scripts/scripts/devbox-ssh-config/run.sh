#!/usr/bin/env bash
#
# configure-ssh.sh
#
# Patches Lima's auto-generated SSH config for the "devbox" VM so that
# connecting to it -- via plain `ssh`, or VSCode Remote-SSH pointed at this
# file -- automatically boots the VM first if it isn't already running.
#
# Lima can regenerate ~/.lima/devbox/ssh.config on every `limactl start`
# (forwarded ports can change), so this script is written to be safely
# re-run: it strips any block it previously inserted before adding a fresh
# one. setup-devbox.sh calls this automatically at the end of its
# interactive (non --ensure) run, so in normal use you don't need to run
# this by hand -- it's here as its own script because the patching logic
# is a distinct step from booting the VM.
#
# Requires: setup-devbox.sh present in the same directory as this script.

set -euo pipefail

VM_NAME="devbox"
SSH_CONFIG="$HOME/.lima/${VM_NAME}/ssh.config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-devbox.sh"

MARK_BEGIN="# >>> devbox-autostart >>>"
MARK_END="# <<< devbox-autostart <<<"

if [[ ! -f "$SSH_CONFIG" ]]; then
  echo "Error: $SSH_CONFIG doesn't exist yet." >&2
  echo "Run setup-devbox.sh first to create/start the VM." >&2
  exit 1
fi

if [[ ! -x "$SETUP_SCRIPT" ]]; then
  echo "Error: expected an executable setup-devbox.sh at $SETUP_SCRIPT" >&2
  echo "(chmod +x it, and keep both scripts in the same directory.)" >&2
  exit 1
fi

HOST_LINE="$(grep -m1 '^Host ' "$SSH_CONFIG" || true)"
if [[ -z "$HOST_LINE" ]]; then
  echo "Error: couldn't find a 'Host' line in $SSH_CONFIG" >&2
  exit 1
fi
HOST_ALIAS="$(awk '{print $2}' <<<"$HOST_LINE")"

# Pass 1: strip any block we previously inserted (idempotency).
tmp="$(mktemp)"
awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
  $0 == b { skip=1; next }
  $0 == e { skip=0; next }
  !skip { print }
' "$SSH_CONFIG" >"$tmp"

# Pass 2: insert the autostart ProxyCommand right after the Host line.
# `setup-devbox.sh --ensure` sends all its own output to stderr, and the
# explicit `1>&2` here is a second, redundant safety net so nothing can
# leak onto stdout and corrupt the SSH data stream. %h/%p expand to this
# Host block's resolved HostName/Port (Lima's forwarded localhost port),
# and `nc` hands the raw TCP connection back to ssh once the VM is up.
awk -v hostline="$HOST_LINE" -v b="$MARK_BEGIN" -v e="$MARK_END" -v setup="$SETUP_SCRIPT" '
  { print }
  $0 == hostline {
    print b
    print "  ProxyCommand " setup " --ensure 1>&2 && exec nc %h %p"
    print e
  }
' "$tmp" >"$SSH_CONFIG"

rm -f "$tmp"

echo "Patched $SSH_CONFIG"
echo
echo "Connect with:"
echo "  ssh -F \"$SSH_CONFIG\" $HOST_ALIAS"
echo
echo "Or point VSCode's Remote-SSH 'Config File' setting at:"
echo "  $SSH_CONFIG"
echo "and connect to host: $HOST_ALIAS"
echo
echo "Either path now boots devbox automatically if it isn't already running."
