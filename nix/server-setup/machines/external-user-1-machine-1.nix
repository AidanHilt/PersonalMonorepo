{ inputs, globals, nixpkgs, ...}:

with inputs;

let
  home-dot-nix = globals.nixConfig + "/home-manager/machine-configs/home-server.nix";

  system = "x86_64-linux";
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
          "/" = {
            device = "/dev/disk/by-uuid/18767db7-d061-4550-9860-3bc6572b57f3";
            fsType = "ext4";
          };

          "/boot" = {
            device = "/dev/disk/by-uuid/4068-E35D";
            fsType = "vfat";
            options = [ "fmask=0077" "dmask=0077" ];
          };

          "/externalStorage" = {
            device = "/dev/disk/by-uuid/DF54-1403";
            fsType = "vfat";
            options = [ "fmask=0000" "dmask=0000" "uid=aidan" "gid=aidan"];
          };
      };

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "24.11";

      networking.hostName = "external-user-1-machine-1";
      networking.networkmanager.enable = true;

      services.openiscsi = {
        enable = true;
        name = hostname;
      };

      services.logind.lidSwitch = "ignore";
    })

    agenix.nixosModules.default

    ../modules/common.nix
    ../modules/rke-primary.nix
    ../modules/rke-universal.nix
  ];
  specialArgs = { inherit inputs globals pkgs; };
}