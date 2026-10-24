{ inputs, globals, pkgs, system, machine-config, ...}:

{
  imports = [
    ../../../modules/shared-disko-configs/vda-single-disk.nix
  ];
}
