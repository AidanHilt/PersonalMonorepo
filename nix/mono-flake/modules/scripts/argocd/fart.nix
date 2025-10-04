{ inputs, globals, pkgs, machine-config, lib, ...}:

let

  fart = pkgs.writeText "fart.sh" ''
    fart () {

    }
  '';
in

{
  environment.interactiveShellInit = ''
    source ${fart}
  '';
}