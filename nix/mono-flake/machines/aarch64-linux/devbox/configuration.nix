# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, machine-config, inputs, globals, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix

    ../../../modules/shared-machine-configs/linux-desktop-terminal.nix

    ../../../modules/roles/nixos/vscode-server.nix
  ];

  security.sudo.wheelNeedsPassword = false;

  virtualisation.rosetta = lib.mkIf pkgs.stdenv.hostPlatform.isAarch64 {
    enable = true;
    mountTag = "vz-rosetta";
  };
}
