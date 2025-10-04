{ inputs, globals, pkgs, machine-config, lib, ...}:

let

  test = pkgs.writeText "test.sh" ''
    test () {

    }
  '';
in

{
  environment.interactiveShellInit = ''
    source ${test}
  '';
}