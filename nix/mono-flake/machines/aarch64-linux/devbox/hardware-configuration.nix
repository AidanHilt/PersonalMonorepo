{ lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.kernelPackages = pkgs.linuxPackages_6_18;

  services.lima.enable = true;

  boot.loader.grub = {
    device = "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  fileSystems."/boot" = {
    device = lib.mkForce "/dev/vda1";
    fsType = "vfat";
  };
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    autoResize = true;
    fsType = "ext4";
    options = [ "noatime" "nodiratime" "discard" ];
  };
}