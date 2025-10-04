{ inputs, globals, pkgs, machine-config, lib, ... }:

let

  $FUNCTION_NAME_BASE = pkgs.writeText "$FUNCTION_NAME_BASE.sh" ''
    $FUNCTION_NAME_BASE () {

    }
  '';
in

{
  environment.interactiveShellInit = ''
    source ${$FUNCTION_NAME_BASE}
  '';
}