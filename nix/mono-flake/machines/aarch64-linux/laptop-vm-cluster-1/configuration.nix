{ config, pkgs, machine-config, inputs, globals, ... }:

{
  home-manager = {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.backupFileExtension = "bak";
    home-manager.extraSpecialArgs = { inherit inputs globals pkgs; };
    home-manager.users.${machine-config.username} = import home-dot-nix {inherit inputs globals pkgs; system = pkgs.system; lib = home-manager.lib; };
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/ROOT";
      fsType = "ext4";
    };

    "/boot" = {
      device = "/dev/disk/by-label/ROOT";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostname = "laptop-vm-cluster-1";

  imports = [
    ../../../modules/machine-categories/homelab-machine.nix
  ];

}