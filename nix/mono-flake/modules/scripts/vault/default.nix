{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ./vault-initialize.nix
  ];
}