{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/master";

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

  outputs = { self, nixpkgs, darwin, home-manager, ... }@inputs:
  let
    system = "aarch64-darwin";
    globals = {
      username = "aidan";
      personalConfig = builtins.fetchGit {
        url = "https://github.com/AidanHilt/PersonalMonorepo.git";
        ref = "feat/nix-darwin";
        rev = "ffe90451db0ff2a1c775531b20b3fb48de0d5b16"; #pragma: allowlist secret
      } + "/nix";
    };

    pkgs = import nixpkgs {
      overlays = [
        inputs.nur.overlay
      ];
      config.allowUnfree = true;

      inherit system;
    };
  in
  {
    darwinConfigurations = {
      "aidans-Virtual-Machine" = import ./machines/virtual-machine.nix { inherit inputs globals pkgs; };
    };
  };
}