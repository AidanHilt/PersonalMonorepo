{ inputs, globals, pkgs, machine-config, lib, ...}:

let

  $SCRIPT_NAME_BASE = pkgs.writeText "$SCRIPT_NAME_BASE.sh" ''
    context-activate-context () {

    }
  '';
in

{
  environment.interactiveShellInit = ''
    source ${$SCRIPT_NAME_BASE}
  '';
}