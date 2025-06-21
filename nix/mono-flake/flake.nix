{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur.url = "github:nix-community/nur";

    personalMonorepo = {
      url = "github:aidanhilt/PersonalMonorepo/staging-cluster-k8s-work";
      flake = false;
    };

    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    systems.url = "github:nix-systems/default";

    # Home Manager items
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
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
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-24.11-darwin";

    darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, darwin, ... }@inputs:
    let
      internalLib = import ./lib-internal/default.nix { inherit nixpkgs darwin inputs; };

      globals = {
        nixConfig = inputs.personalMonorepo + "/nix";
      };

      systems = import inputs.systems;

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
      darwinConfigurations = aarch64DarwinConfigs;
      nixosConfigurations = allConfigs.nixosConfigurations;
      #  {
      #   # How we build our bootstrap iso images
      #   iso_image_x86 = nixpkgs.lib.nixosSystem {
      #     system = "x86_64-linux";
      #     modules = [
      #       (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
      #       inputs.home-manager.nixosModules.home-manager
      #       ./modules/nixos/bootstrap-image.nix
      #     ];
      #   };

      #   iso-image-aarch64 = nixpkgs.lib.nixosSystem {
      #     system = "aarch64-linux";

      #     specialArgs = {
      #       pkgs = pkgsFor.aarch64-linux;
      #       inherit inputs globals;
      #     };

      #     modules = [
      #       (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
      #       ./modules/roles/nixos/bootstrap-image.nix

      #       inputs.home-manager.nixosModules.home-manager {
      #         home-manager.useGlobalPkgs = true;
      #         home-manager.useUserPackages = true;
      #         home-manager.backupFileExtension = "bak";
      #         home-manager.extraSpecialArgs = { inherit inputs globals; pkgs = pkgsFor.aarch64-linux; };
      #         home-manager.users.root = import ./home-manager/shared-configs/server.nix {
      #           inherit inputs globals;
      #           pkgs = pkgsFor.aarch64-linux;
      #           system = "aarch64-linux";
      #           lib = inputs.home-manager.nixosModules.home-manager.lib;
      #         };
      #       }

      #       (
      #         {pkgs, ...}: {
      #           isoImage = {
      #             makeEfiBootable = true;
      #             makeUsbBootable = true;
      #             squashfsCompression = "zstd -Xcompression-level 6"; #way faster build time
      #           };
      #         }
      #       )
      #     ];
      #   };
      # };
  };
}
