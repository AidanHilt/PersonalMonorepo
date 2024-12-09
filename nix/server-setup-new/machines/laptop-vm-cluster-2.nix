{ inputs, globals, nixpkgs, ...}:

with inputs;

let
  home-dot-nix = globals.nixConfig + "/home-manager/machine-configs/home-server.nix";

  system = "aarch64-linux";
  pkgs = import nixpkgs {
    config.allowUnfree = true;
    inherit system;
  };

  serverAddr = "192.168.86.227";
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
          device = "/dev/disk/by-uuid/4574ed8a-7849-4343-90e6-6395045e322d";
          fsType = "ext4";
        };

      "/boot" = {
          device = "/dev/disk/by-uuid/E7D5-910C";
          fsType = "vfat";
          options = [ "fmask=0077" "dmask=0077" ];
        };
      };

      age.secrets.rke-token = {
        file = globals.nixConfig + "/secrets/rke-token-mac-cluster.age";
        path = "/var/lib/rancher/rke2/server/token";
        owner = "aidan";
        mode = "744";
      };

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      nixpkgs.hostPlatform = "aarch64-linux";
      system.stateVersion = "24.11";

      networking.hostName = "laptop-vm-cluster-2";
      networking.interfaces.enp0s1.ipv4.addresses = [
        {
          address = "192.168.86.21";
          prefixLength = 24;
        }
      ];
    })

    agenix.nixosModules.default

    ../modules/common.nix
    #../modules/rke-secondary.nix
    ../modules/adguard.nix
  ];
  specialArgs = { inherit inputs globals pkgs serverAddr; };
}