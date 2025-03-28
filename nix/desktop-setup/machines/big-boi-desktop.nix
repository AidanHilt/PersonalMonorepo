{ inputs, globals, nixpkgs, ...}:

with inputs;

let
  home-dot-nix = inputs.personalMonorepo + "/nix/home-manager/machine-configs/big-boi-desktop.nix";

  system = "aarch64-linux";
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
      networking.hostName = "big-boi-desktop";
      nixpkgs.hostPlatform = "aarch64-linux";
    })

    inputs.agenix.nixosModules.default

    ../modules/common.nix
    ../modules/rclone.nix
  ];
  specialArgs = { inherit inputs globals; };
}