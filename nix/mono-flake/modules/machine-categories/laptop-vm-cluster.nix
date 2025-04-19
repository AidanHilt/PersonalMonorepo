{ inputs, globals, pkgs, machine-config, ...}:


{
  imports = [
    ../roles/nixos/homelab-node.nix
  ];

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
}