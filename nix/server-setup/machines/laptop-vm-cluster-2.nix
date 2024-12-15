{ inputs, globals, nixpkgs, ...}:

with inputs;

let
  home-dot-nix = globals.nixConfig + "/home-manager/machine-configs/home-server.nix";

  system = "aarch64-linux";
  pkgs = import nixpkgs {
    config.allowUnfree = true;
    inherit system;
  };

  serverAddr = "192.168.86.20";
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
          device = "/dev/disk/by-uuid/4fc9779c-69d2-4d71-910b-0e39de53e09d";
          fsType = "ext4";
        };

      "/boot" = {
          device = "/dev/disk/by-uuid/5370-5201";
          fsType = "vfat";
          options = [ "fmask=0077" "dmask=0077" ];
        };
      };

      age.secrets.rke-token = {
        file = globals.nixConfig + "/secrets/rke-token-mac-cluster.age";
        path = "/var/lib/rancher/rke2/server/token";
        symlink = false;
        mode = "777";
      };

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      nixpkgs.hostPlatform = "aarch64-linux";
      system.stateVersion = "24.11";

      networking = {
        defaultGateway = "192.168.86.1";
        hostName = "laptop-vm-cluster-2";
        nameservers = [ "192.168.86.3" ];
        interfaces.enp0s1.ipv4.addresses = [
          {
            address = "192.168.86.21";
            prefixLength = 24;
          }
        ];
      };
    })

    agenix.nixosModules.default

    ../modules/common.nix
    ../modules/rke-secondary.nix
    ../modules/rke-universal.nix
    ../modules/adguard.nix
    ../modules/keepalived-staging.nix
  ];
  specialArgs = { inherit inputs globals pkgs serverAddr; };
}