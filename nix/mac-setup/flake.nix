{
  description = "A flake managing MacOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-24.11-darwin";

    darwin.url = "github:lnl7/nix-darwin/nix-darwin-24.11";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nur.url = "github:nix-community/nur";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    poetry2nix.url = "github:nix-community/poetry2nix";
    poetry2nix.inputs.nixpkgs.follows = "nixpkgs";

    personalMonorepo = {
      url = "github:aidanhilt/PersonalMonorepo/feat/default-extensions-remote";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, darwin, home-manager, ... }@inputs:
  let
    system = "aarch64-darwin";
    globals = {
      username = "aidan";
      nixConfig = inputs.personalMonorepo + "/nix";
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
    darwinConfigurations = {
      # Work machine name
      "Aidans-MacBook-Pro" = import ./machines/work-macbook.nix { inherit inputs globals pkgs; };
      # Personal machine name
      hyperion = import ./machines/personal-macbook.nix { inherit inputs globals pkgs; };
    };
  };
}
