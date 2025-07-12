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
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs globals pkgs machine-config; };
    users.${machine-config.username} = import ./home.nix {inherit inputs globals pkgs machine-config; system = pkgs.system; lib = inputs.home-manager.lib; };
  };

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  users.users."${machine-config.username}".hashedPassword = "$y$j9T$47Fj09DL3ycTvCft06SAE1$FIYj3k6p1wzVOrZI.aLp5s7IBblimqa1/k/ACv9hiC/";

  # Enable networking
  networking.networkmanager.enable = true;
}
