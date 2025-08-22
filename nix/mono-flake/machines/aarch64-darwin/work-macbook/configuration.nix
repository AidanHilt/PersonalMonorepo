{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ../../../modules/roles/darwin/darwin-universal.nix
    ../../../modules/roles/darwin/work.nix

    ../../../modules/roles/universal/development-machine.nix
  ];
}