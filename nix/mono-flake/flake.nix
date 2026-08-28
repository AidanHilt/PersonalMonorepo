{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
    };

    nur.url = "github:nix-community/nur";

    personalMonorepo = {
      url = "github:aidanhilt/PersonalMonorepo/main";
      flake = false;
    };

    scripts = {
      url = "github:aidanhilt/PersonalMonorepo/project-lockstep/release-mgmt?dir=nix/scripts";
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

    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/01ef07c1c8bc8d9db9c0c9c59a8fea701b7f5a34";

    # Darwin-specific items
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-26.05-darwin";

    darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
  };

  outputs = { self, nixpkgs, darwin, ... }@inputs:
    let
      internalLib = import ./lib-internal/default.nix { inherit nixpkgs darwin inputs; };

      globals = {
        nixConfig = inputs.personalMonorepo + "/nix";
        personalMonorepoBranch = "master";
        personalMonorepoURL = "https://github.com/AidanHilt/PersonalMonorepo";
      };

      allSystems = import inputs.systems;
      systems = nixpkgs.lib.filter (sys: builtins.pathExists (./machines + "/${sys}")) allSystems;

      baseOverlays = [
        inputs.nur.overlays.default
        inputs.agenix.overlays.default
        inputs.nix-vscode-extensions.overlays.default
        inputs.nix-cachyos-kernel.overlays.default
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
