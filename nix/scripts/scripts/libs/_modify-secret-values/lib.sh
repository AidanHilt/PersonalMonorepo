#!/bin/bash
# Concatenated into writeShellApplication's run.sh, which applies
# set -euo pipefail; keep this safe under those options.

modify-secret-values() {
  local YQ_STRING="$1"
  local FILE_NAME="$2"

  yaml-edit-apply "$YQ_STRING | to_entries | sort_by(.key) | from_entries" "$FILE_NAME"
}
