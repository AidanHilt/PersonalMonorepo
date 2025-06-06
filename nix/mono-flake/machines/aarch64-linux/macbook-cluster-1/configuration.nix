# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, machine-config, inputs, globals, ... }:

{
  imports = [
      ../../../modules/hardware-configs/utm.nix
      ../../../modules/disko-configs/vda-single-disk.nix

      ../../../modules/roles/nixos/linux-universal.nix
      ../../../modules/roles/nixos/homelab-node.nix
    ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs globals pkgs machine-config; };
    users.${machine-config.username} = import ../../../home-manager/shared-configs/server.nix {inherit inputs globals pkgs machine-config; system = pkgs.system; lib = inputs.home-manager.lib; };
  };

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  users.users."${machine-config.username}".hashedPassword = "$y$j9T$47Fj09DL3ycTvCft06SAE1$FIYj3k6p1wzVOrZI.aLp5s7IBblimqa1/k/ACv9hiC/";

  # Enable networking
  networking.networkmanager.enable = true;

}
