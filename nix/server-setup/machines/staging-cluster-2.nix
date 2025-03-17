{ inputs, globals, nixpkgs, ...}:

with inputs;

let
  home-dot-nix = globals.nixConfig + "/home-manager/machine-configs/home-server.nix";

  system = "x86_64-linux";
  pkgs = import nixpkgs {
    config.allowUnfree = true;
    inherit system;
  };

  serverAddr = "192.168.86.23";
  hostname = "staging-cluster-2";
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
          device = "/dev/disk/by-label/ROOTDIR";
          fsType = "ext4";
        };
      };


      age.secrets.rke-token = {
        file = globals.nixConfig + "/secrets/rke-token-staging-cluster.age";
        path = "/var/lib/rancher/rke2/server/token";
        symlink = false;
        mode = "444";
      };

      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "24.11";

      networking = {
        defaultGateway = "192.168.86.1";
        hostName = hostname;
        nameservers = [ "192.168.86.3" ];
        interfaces.enp0s3.ipv4.addresses = [
          {
            address = serverAddr;
            prefixLength = 24;
          }
        ];
      };

      services.openiscsi = {
        enable = true;
        name = hostname;
      };

      #=========================================================================
      # This is all virtualbox-specific stuff. I don't totally know how it works
      #=========================================================================
      boot.loader.grub.enable = true;
      boot.loader.grub.device = "/dev/sda";
      boot.loader.grub.useOSProber = true;

      boot.initrd.availableKernelModules = [ "ata_piix" "ohci_pci" "ehci_pci" "ahci" "sd_mod" "sr_mod" ];
      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ ];
      boot.extraModulePackages = [ ];

      swapDevices = [ ];

      virtualisation.virtualbox.guest.enable = true;
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