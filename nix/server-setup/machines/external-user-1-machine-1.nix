{ inputs, globals, nixpkgs, ...}:

with inputs;

let
  home-dot-nix = globals.nixConfig + "/home-manager/machine-configs/home-server.nix";

  system = "aarch64-linux";
  pkgs = import nixpkgs {
    config.allowUnfree = true;
    inherit system;
  };

  hostname = "external-user-1-machine-1";
in

nixpkgs.lib.nixosSystem {
  modules = [
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "bak";
      home-manager.extraSpecialArgs = { inherit inputs globals pkgs; };
      home-manager.users.aidan = import home-dot-nix {inherit inputs globals pkgs; system = pkgs.system; lib = home-manager.lib; };
      }

    ({ inputs, globals, ... }: {
      fileSystems = {
        "/" =
          { device = "/dev/disk/by-uuid/bb7bfa45-7bdc-471d-a985-8cb160ca9b89";
            fsType = "ext4";
          };

        "/boot" =
          { device = "/dev/disk/by-uuid/80F3-C7B2";
            fsType = "vfat";
            options = [ "fmask=0077" "dmask=0077" ];
          };
      };

        fileSystems = {
        "/" = {
          device = "/dev/disk/by-uuid/6e507691-a02a-434d-a5cd-fb505d51dbee";
          fsType = "ext4";
        };

        "/boot" = {
          device = "/dev/disk/by-uuid/30FE-4BD0";
          fsType = "vfat";
          options = [ "fmask=0077" "dmask=0077" ];
        };
      };

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      nixpkgs.hostPlatform = "aarch64-linux";
      system.stateVersion = "24.11";

      services.openiscsi = {
        enable = true;
        name = hostname;
      };
    })

    agenix.nixosModules.default

    ../modules/common.nix
    ../modules/rke-primary.nix
    ../modules/rke-universal.nix
  ];
  specialArgs = { inherit inputs globals pkgs; };
}