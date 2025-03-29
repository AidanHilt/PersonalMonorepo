{ inputs, globals, nixpkgs, pkgs, ...}:

with inputs;

let
  home-dot-nix = inputs.personalMonorepo + "/nix/home-manager/machine-configs/big-boi-desktop.nix";

  machine-config = {
    username = "aidan";
  };
in
{
  imports = [
    import ../modules/common.nix { inherit machine-config; }
    ../modules/rclone.nix
  ];

  specialArgs = machine-config;

  networking.hostName = "big-boi-desktop";

  fileSystems = {
    "/" = {
    device = "/dev/disk/by-label/DESKTOPROOT";
    fsType = "ext4";
    };

    "/boot" = {
      device = "/dev/disk/by-label/BOOT";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}