#!/bin/bash
# Concatenated into writeShellApplication's run.sh, which applies
# set -euo pipefail; keep this safe under those options.

modify-ingress-values() {
  local YQ_STRING="$1"
  local FILE_NAME="$2"

  yaml-edit-apply "$YQ_STRING" "$FILE_NAME"
  yaml-edit-reorder "$FILE_NAME" "hostnames:" ".hostnames" "1" \
    "del(.hostnames) | to_entries | sort_by(.key) | from_entries" ""
}
