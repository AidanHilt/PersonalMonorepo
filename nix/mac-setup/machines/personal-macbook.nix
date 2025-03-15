{ inputs, globals, pkgs, ...}:

with inputs;

let
  home-dot-nix = globals.nixConfig + "/home-manager/machine-configs/personal-macbook.nix";
  shared-modules = globals.nixConfig + "/shared-modules";
in

darwin.lib.darwinSystem {
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

      networking.hostName = "hyperion";

    })

    agenix.darwinModules.default

    ../modules/common.nix
    ../modules/personal.nix
    import shared-modules + "/kubernetes.nix"
  ];
  specialArgs = { inherit inputs globals; };
}