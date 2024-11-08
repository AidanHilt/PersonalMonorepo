{ inputs, globals, pkgs, ...}:

with inputs;

let
  home-dot-nix = inputs.personalMonorepo + "/nix/home-manager/machine-configs/personal-macbook.nix";
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
      };

      networking.hostName = "laptop-vm-cluster-1";
      pkgs.hostPlatform = "aarch64-linux";
    })
  ];
  specialArgs = { inherit inputs globals; };
}