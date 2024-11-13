{ inputs, globals, nixpkgs, ...}:

with inputs;

let
  home-dot-nix = inputs.personalMonorepo + "/nix/home-manager/machine-configs/wsl.nix";

  system = "x86_64-linux";
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
      networking.hostName = "wsl-machine";
      nixpkgs.hostPlatform = "x86_64-linux";

      wsl = {
        enable = true;
        defaultUser = "nixos";
      };
    })

    inputs.wsl.nixosModules.wsl
  ];
}