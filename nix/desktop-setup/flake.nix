{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

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

  outputs = { self, nixpkgs, agenix, home-manager, ... }@inputs:
  let
    globals = {
      nixConfig = inputs.personalMonorepo + "/nix";
      username = "nixos";
    };

    pkgs = import nixpkgs {
      overlays = [
        inputs.nur.overlays.default
      ];
      config.allowUnfree = true;

      inherit system;
    };
  in
  {
    nixosConfigurations = {
      wsl-machine = import ./machines/wsl-machine.nix { inherit inputs globals nixpkgs; };
      vm-desktop = import ./machines/vm-desktop.nix { inherit inputs globals nixpkgs; };
    };
  };
}
