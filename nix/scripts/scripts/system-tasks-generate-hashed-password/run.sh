#!/bin/bash

# @lib: printing-and-output
# @lib: args-and-help

set -euo pipefail

#Default values
PASSWORD=""

args_description "Generate a hashed password, interactively or from a given string."
args_example "$0                   # Interactive mode"
args_example "$0 -p some-password # Named password argument"
args_value "-p" "--password-string" PASSWORD "PASSWORD" "A text string representing the password you want to hash"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

if [[ -z "$PASSWORD" ]]; then
  while true; do
    read -sr -p "Please enter the password you would like to generate a hash for: " PASSWORD
    if [[ -n "$PASSWORD" ]]; then
      echo ""
      break
    else
      echo "Password cannot be empty."
    fi
  done
fi

HASHED_PASSWORD=$(mkpasswd "$PASSWORD")

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
