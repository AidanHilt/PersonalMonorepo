{ inputs, globals, pkgs, machine-config, lib, ...}:

let
system-tasks-generate-hashed-password = pkgs.writeShellScriptBin "system-tasks-generate-hashed-password" ''
#!/bin/bash

set -euo pipefail

#Default values
PASSWORD=""

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  -p --password-string  A text string representing the password you want to hash"
  echo "Examples:"
  echo "  $0                   # Interactive mode"
  echo "  $0 -p some-password # Named password argument"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--password-string)
      PASSWORD="$2"
      shift 2
      ;;
    *)
      echo "Unknown option $1"
      usage
      ;;
  esac
done

if [[ -z "$PASSWORD" ]]; then
  while true; do
    read -s -p "Please enter the password you would like to generate a hash for: " PASSWORD
    if [[ -n "$PASSWORD" ]]; then
      echo ""
      break
    else
      echo "Password cannot be empty."
    fi
  done
fi 

HASHED_PASSWORD=$(mkpasswd $PASSWORD)

if command -v pbcopy >/dev/null 2>&1; then
  # macOS
  echo "$HASHED_PASSWORD" | pbcopy
  echo "Copied to clipboard using pbcopy"
elif command -v xclip >/dev/null 2>&1; then
  # Linux with xclip
  echo "$HASHED_PASSWORD" | xclip -selection clipboard
  echo "Copied to clipboard using xclip"
elif command -v wl-copy >/dev/null 2>&1; then
  # Wayland
  echo "$HASHED_PASSWORD" | wl-copy
  echo "Copied to clipboard using wl-copy"
else
  echo "Warning: No clipboard utility found (pbcopy, xclip, wl-copy)"
  echo "The hashed password is: $HASHED_PASSWORD"
fi
'';
in

{
  environment.systemPackages = [
    system-tasks-generate-hashed-password
  ];
}