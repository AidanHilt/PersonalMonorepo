# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, machine-config, inputs, globals, ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix

    ../../../modules/shared-machine-configs/linux-desktop.nix
    ../../../modules/roles/nixos/vscode-server.nix
    ../../../modules/roles/nixos/nvidia.nix
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    useOSProber = true;
  };

  users.users."${machine-config.username}".hashedPassword = "$y$j9T$47Fj09DL3ycTvCft06SAE1$FIYj3k6p1wzVOrZI.aLp5s7IBblimqa1/k/ACv9hiC/";

  # Enable networking
  networking.networkmanager.enable = true;
}
