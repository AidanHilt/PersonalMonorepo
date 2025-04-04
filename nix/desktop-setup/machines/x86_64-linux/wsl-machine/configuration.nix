{ inputs, globals, nixpkgs, ...}:

with inputs;

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
    inputs.agenix.nixosModules.default

  ];
  specialArgs = { inherit inputs globals; };
}