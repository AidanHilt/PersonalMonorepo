{ inputs, globals, pkgs, machine-config, lib, ...}:

let

  add_import_to_nix = pkgs.writeText "add_import_to_nix.sh" ''
    add_import_to_nix() {
      FILEPATH="$1"
      FILENAME="$2"

      IMPORT_LINE="./''${FILENAME}"

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
  environment.interactiveShellInit = ''
    source ${add_import_to_nix}
  '';
}