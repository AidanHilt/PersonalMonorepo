{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ../../../modules/roles/darwin/darwin-universal.nix
    ../../../modules/roles/darwin/personal.nix

    ../../../modules/roles/universal/development-machine.nix
    ../../../modules/roles/universal/linux-admin.nix
    ../../../modules/roles/universal/nixos-admin.nix
  ];
}