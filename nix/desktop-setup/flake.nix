{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    nur.url = "github:nix-community/nur";

    personalMonorepo = {
      url = "github:aidanhilt/PersonalMonorepo/staging-cluster-k8s-work";
      flake = false;
    };

    poetry2nix.url = "github:nix-community/poetry2nix";
    poetry2nix.inputs.nixpkgs.follows = "nixpkgs";

    wsl.url = "github:nix-community/NixOS-WSL";
    wsl.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      globals = {
        nixConfig = inputs.personalMonorepo + "/nix";
      };

      mkSystem = name: system: nixpkgs: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs globals nixpkgs };
        modules = [
          ./machines/${name}.nix
        ];
    };
    in {
      nixosConfigurations = {
        vm-desktop = mkSystem "vm-desktop" "aarch64-linux" inputs.nixpkgs {};
        wsl-machine = import ./machines/wsl-machine.nix { inherit inputs globals nixpkgs; };
      };
  };
}
