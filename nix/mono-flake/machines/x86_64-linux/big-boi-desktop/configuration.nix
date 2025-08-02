# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, machine-config, inputs, globals, ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix

    ../../../modules/shared-machine-configs/linux-desktop.nix

    ../../../modules/roles/nixos/fixed-ip-machine.nix
    ../../../modules/roles/nixos/nvidia.nix
    ../../../modules/roles/nixos/vscode-server.nix

    ../../../roles/universal/development-machine.nix
    ../../../roles/universal/linux-admin.nix
    ../../../roles/universal/nixos-admin.nix
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    useOSProber = true;
  };
}
