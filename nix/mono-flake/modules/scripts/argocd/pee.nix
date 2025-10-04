{ inputs, globals, pkgs, machine-config, lib, ...}:

let

  pee = pkgs.writeText "pee.sh" ''
    pee () {

    }
  '';
in

{
  environment.interactiveShellInit = ''
    source ${pee}
  '';
}