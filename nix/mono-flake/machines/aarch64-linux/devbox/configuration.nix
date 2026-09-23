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

  # virtualisation.rosetta = {
  #   enable = true;
  #   mountTag = "vz-rosetta";
  # };

  fileSystems."/mnt/shared" = {
    device = "share";
    fsType = "virtiofs";
  };

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
}

