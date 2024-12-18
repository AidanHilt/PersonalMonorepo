{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/master";

    nixpkgs-old-terraform.url = "github:nixos/nixpkgs/unstable?rev=5a8650469a9f8a1958ff9373bd27fb8e54c4365d";

    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nur.url = "github:nix-community/nur";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    poetry2nix.url = "github:nix-community/poetry2nix";
    poetry2nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, darwin, home-manager, nixpkgs-old-terraform ... }@inputs:
  let
    system = "aarch64-darwin";
    globals = {
      username = "aidan";
      personalConfig = builtins.fetchGit {
        url = "https://github.com/AidanHilt/PersonalMonorepo.git";
        ref = "master";
        rev = "634ef9013cd29b8f414a81c0e4b3bdb0b48c0a5b"; #pragma: allowlist secret
      } + "/nix";
    };

    pkgs = import nixpkgs {
      overlays = [
        inputs.nur.overlay
      ];
      config.allowUnfree = true;

      inherit system;
    };

    pkgs-terraform = import nixpkgs-old-terraform {
      config.allowUnfree = true;

      inherit system;
    };
  in
  {
    darwinConfigurations = {
      # Work machine name
      "Aidans-MacBook-Pro" = import ./machines/work-macbook.nix { inherit inputs globals pkgs pkgs-terraform; };
      # Personal machine name
      hyperion = import ./machines/personal-macbook.nix { inherit inputs globals pkgs; };
    };
  };
}
