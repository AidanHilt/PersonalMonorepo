{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ../../scripts/mono-flake/default.nix
    ../../scripts/nixos/default.nix
  ];

  environment.systemPackages = with pkgs; [

  ];
}