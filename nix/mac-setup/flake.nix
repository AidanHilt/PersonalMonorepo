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
        ref = "feat/post-install-nix-extras";
        rev = "a462cb6af56544ce38b25771ec48a72f5d956c8d"; #pragma: allowlist secret
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
      # Work machine name
      "Aidans-MacBook-Pro" = import ./machines/work-macbook.nix { inherit inputs globals pkgs; };
      # Personal machine name
      hyperion = import ./machines/personal-macbook.nix { inherit inputs globals pkgs; };
    };
  };
}
