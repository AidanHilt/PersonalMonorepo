#!/bin/bash
# Concatenated into writeShellApplication's run.sh, which applies
# set -euo pipefail; keep this safe under those options.

add-import-to-nix() {
  local FILEPATH="$1"
  local FILENAME="$2"
  local IMPORT_LINE="  ./${FILENAME}"

  awk -v import="  ${IMPORT_LINE}" '
      /imports = \[/ {
        print
        print import
        next
      }
      { print }
    ' "$FILEPATH" >"${FILEPATH}.tmp"

  mv "${FILEPATH}.tmp" "$FILEPATH"
}
