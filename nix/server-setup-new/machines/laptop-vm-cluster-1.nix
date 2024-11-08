{ inputs, globals, nixpkgs, ...}:

with inputs;

let
  home-dot-nix = inputs.personalMonorepo + "/nix/home-manager/machine-configs/home-server.nix";

  system = "aarch64-linux";
  pkgs = import nixpkgs {
    config.allowUnfree = true;
    inherit system;
  };
in

nixpkgs.lib.nixosSystem {
  modules = [

    home-manager.darwinModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "bak";
      home-manager.extraSpecialArgs = { inherit inputs globals pkgs; };
      home-manager.users.aidan = import home-dot-nix {inherit inputs globals pkgs; system = pkgs.system; lib = home-manager.lib; };
      }

    ({ inputs, globals, ... }: {
      users.users.aidan = {
        home = "/Users/aidan";
        group = "aidan";
        isNormalUser = true;
        };

      fileSystems = {
        "/" = {
          device = "/dev/disk/by-uuid/475c3eec-824f-4834-b40a-52845766e530";
          fsType = "ext4";
        };

        "/boot" = {
          device = "/dev/disk/by-uuid/AAC8-AE1C";
          fsType = "vfat";
          options = [ "fmask=0077" "dmask=0077" ];
        };
      };

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      networking.hostName = "laptop-vm-cluster-1";
      nixpkgs.hostPlatform = "aarch64-linux";
    })
  ];
  specialArgs = { inherit inputs globals; };
}