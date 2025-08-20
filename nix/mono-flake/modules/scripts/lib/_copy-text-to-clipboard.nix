{ inputs, globals, pkgs, machine-config, lib, ...}:

let
_copy-text-to-clipboard = pkgs.writeShellScriptBin "_copy-text-to-clipboard" ''
#!/bin/bash

set -euo pipefail
if command -v pbcopy >/dev/null 2>&1; then
  echo "$1" | pbcopy
  echo "Copied to clipboard using pbcopy"
elif command -v xclip >/dev/null 2>&1; then
  echo "$1" | xclip -selection clipboard
  echo "Copied to clipboard using xclip"
elif command -v wl-copy >/dev/null 2>&1; then
  echo "$1" | wl-copy
  echo "Copied to clipboard using wl-copy"
else
  echo "Warning: No clipboard utility found (pbcopy, xclip, wl-copy)"
fi
'';
in

{
  environment.systemPackages = [
    _copy-text-to-clipboard
  ];
}