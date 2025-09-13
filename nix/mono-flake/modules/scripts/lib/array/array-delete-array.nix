{ inputs, globals, pkgs, machine-config, lib, ...}:

let

   = pkgs.writeText ".sh" ''
    context-activate-context () {

    }
  '';
in

{
  environment.interactiveShellInit = ''
    source ${}
  '';
}