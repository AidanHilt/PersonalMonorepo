# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, machine-config, inputs, globals, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix

    ../../../modules/roles/nixos/linux-universal.nix

    ../../../modules/roles/universal/development-machine.nix
    ../../../modules/roles/universal/personal-development.nix

    ../../../modules/roles/nixos/vscode-server.nix
  ];

  environment.systemPackages = with pkgs; [
    ghostty.terminfo
  ];

  security.sudo.wheelNeedsPassword = false;

  # virtualisation.rosetta = lib.mkIf pkgs.stdenv.hostPlatform.isAarch64 {
  #   enable = true;
  #   mountTag = "vz-rosetta";
  # };

  users.users.root = {
    initialPassword = "root";
  };

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
}

