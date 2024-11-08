{
  description = "A flake managing server configurations";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    personalMonorepo = {
      url = "github:aidanhilt/PersonalMonorepo/feat/nix-server-setup";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, agenix, home-manager, ... }@inputs:
  let
    globals = {
      username = "aidan";
      personalConfig = inputs.personalMonorepo + "/nix";
    };
  in
  {
    nixosConfigurations = {
      laptop-vm-cluster-1 = import ./machines/laptop-vm-cluster-1.nix { inherit inputs globals nixpkgs; };
    };
  };
}
