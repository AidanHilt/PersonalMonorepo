{ inputs, globals, nixpkgs, ...}:

with inputs;

let
  home-dot-nix = inputs.personalMonorepo + "/nix/home-manager/machine-configs/big-boi-desktop.nix";

  system = "aarch64-linux";
  pkgs = import nixpkgs {
    config.allowUnfree = true;
    inherit system;
  };

in

nixpkgs.lib.nixosSystem {
  modules = [
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "bak";
      home-manager.extraSpecialArgs = { inherit inputs globals pkgs; };
      home-manager.users.nixos = import home-dot-nix {inherit inputs globals pkgs; system = pkgs.system; lib = home-manager.lib; };
    }

    ({ inputs, globals, ...}: {
      networking.hostName = "big-boi-desktop";
      nixpkgs.hostPlatform = "aarch64-linux";

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

      networking.hostName = "big-boi-desktop";

    })

    inputs.agenix.nixosModules.default

    ../modules/common.nix
    ../modules/rclone.nix
  ];
  specialArgs = { inherit inputs globals; };
}