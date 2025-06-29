{ inputs, globals, pkgs, system, machine-config, ...}:

{
  imports = [
    ../../../modules/disko-configs/vda-single-disk.nix
  ];
}
