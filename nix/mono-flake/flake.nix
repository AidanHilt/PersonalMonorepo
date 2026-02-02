{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur.url = "github:nix-community/nur";

    personalMonorepo = {
      url = "github:aidanhilt/PersonalMonorepo/master";
      flake = false;
    };

    comin = {
      url = "github:nlewo/comin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    systems.url = "github:nix-systems/default";

    # Home Manager items
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Linux-specific items
    wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Darwin-specific items
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-25.11-darwin";

    darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    # Versioning stuff
    nixpkgs-terragrunt.url = "github:nixos/nixpkgs/0024e310e51151ee27d710e1f2fdf5e9c293da0b";
    nixpkgs-terraform.url = "github:nixos/nixpkgs/0472f3c9c5618c9675fc8dcc9e6ea484a5590d6d";
    nixpkgs-xone.url = "github:fxzzi/nixpkgs/f621e42319dbde5153c77fd7716c82853839b90b";
  };

  outputs = { self, nixpkgs, darwin, ... }@inputs:
    let
      internalLib = import ./lib-internal/default.nix { inherit nixpkgs darwin inputs; };

      globals = {
        nixConfig = inputs.personalMonorepo + "/nix";
        personalMonorepoBranch = "feat/external-user-1-final-retry";
        personalMonorepoURL = "https://github.com/AidanHilt/PersonalMonorepo";
      };

      allSystems = import inputs.systems;
      systems = nixpkgs.lib.filter (sys: builtins.pathExists (./machines + "/${sys}")) allSystems;

      baseOverlays = [
        inputs.nur.overlays.default
        inputs.agenix.overlays.default
        inputs.nix-vscode-extensions.overlays.default
      ];

      platformOverlays = {
        "aarch64-darwin" = [
          (self: super: { nodejs = super.nodejs_22; })
        ];
      };

      pkgsFor = internalLib.packages.genPkgsFor
        inputs.systems
        baseOverlays
        platformOverlays;

      allConfigs = internalLib.configs.buildAllConfigs {
        inherit systems pkgsFor inputs globals;
        machinesDir = ./machines;
        overlays = baseOverlays;
        inherit platformOverlays;
      };

    in {
      darwinConfigurations = allConfigs.darwinConfigurations;
      nixosConfigurations = allConfigs.nixosConfigurations;
  };
}
