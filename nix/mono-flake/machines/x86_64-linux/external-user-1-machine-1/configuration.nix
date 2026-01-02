# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, machine-config, inputs, globals, lib, ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix

    ../../../modules/roles/nixos/linux-universal.nix
    ../../../modules/shared-machine-configs/homelab-node.nix
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  services.logind.lidSwitch = "ignore";

  boot.supportedFilesystems = [ "ntfs" ];

  fileSystems."/externalStorage" = {
    device = "/dev/disk/by-uuid/4C0A704D0A703654";
    fsType = "ntfs-3g";
    options = [ "rw" "uid=1000" "gid=1000" ];
  };

  networking.networkmanager.enable = true;
}
