{ inputs, globals, pkgs, machine-config, lib, ...}:

let

  poo = pkgs.writeText "poo.sh" ''
    poo () {

    }
  '';
in

{
  environment.interactiveShellInit = ''
    source ${poo}
  '';
}