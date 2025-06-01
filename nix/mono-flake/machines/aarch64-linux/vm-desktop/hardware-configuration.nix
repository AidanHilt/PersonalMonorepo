{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [
      (modulesPath + "/profiles/qemu-guest.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # fileSystems = {
  #   "/" = {
  #   device = "/dev/disk/by-label/DESKTOPROOT";
  #   fsType = "ext4";
  #   };

  #   "/boot" = {
  #     device = "/dev/disk/by-label/BOOT";
  #     fsType = "vfat";
  #     options = [ "fmask=0077" "dmask=0077" ];
  #   };
  # };


  disko.devices = {
    disk = {
      vda = {
        device = "/dev/vda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "100M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp0s1.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
