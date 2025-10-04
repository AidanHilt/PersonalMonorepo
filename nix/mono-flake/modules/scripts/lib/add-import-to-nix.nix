{ pkgs, ...  }:

let
  add-import-to-nix = pkgs.writeText "add-import-to-nix.sh" ''
  add-import-to-nix() {
    FILEPATH="$1"
    FILENAME="$2"

    export IMPORT_LINE="./''${FILENAME}"

    awk -v import="  ''${IMPORT_LINE}" '
      /imports = \[/ {
        print
        print import
        next
      }
      { print }
    ' "''$FILEPATH" > "''${FILEPATH}.tmp"

    mv "''${FILEPATH}.tmp" "''$FILEPATH"
  }
  '';
in

{
  add-import-to-nix = add-import-to-nix;
}