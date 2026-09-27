{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ../../../modules/roles/darwin/darwin-universal.nix
    ../../../modules/roles/darwin/personal.nix
  ];
}