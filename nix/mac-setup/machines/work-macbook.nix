{ inputs, globals, pkgs, ...}:

with inputs;

let
  home-dot-nix = globals.personalConfig + "/home-manager/machine-configs/work-macbook.nix";
in

darwin.lib.darwinSystem {
  modules = [

    home-manager.darwinModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "bak";
      home-manager.extraSpecialArgs = { inherit inputs globals pkgs; };
      home-manager.users.ahilt = import home-dot-nix {inherit inputs globals pkgs; system = pkgs.system; lib = home-manager.lib; };
      }

    ({ inputs, globals, ... }: {
      users.users.ahilt = {
        home = "/Users/ahilt";
      };

      networking.hostName = "Aidans-Macbook-Pro";
    })

    ../modules/common.nix
    ../modules/work.nix

  ];
  specialArgs = { inherit inputs globals; };
}