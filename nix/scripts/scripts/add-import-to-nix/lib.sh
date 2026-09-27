#!/bin/bash

add-import-to-nix() {
  FILEPATH="$1"
  FILENAME="$2"

  export IMPORT_LINE="  ./''${FILENAME}"

  awk -v import="  ''${IMPORT_LINE}" '
      /imports = \[/ {
        print
        print import
        next
      }
      { print }
    ' "''$FILEPATH" >"''${FILEPATH}.tmp"

  mv "''${FILEPATH}.tmp" "''$FILEPATH"
}
