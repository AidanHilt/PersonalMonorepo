{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";

    darwin.url = "github:lnl7/nix-darwin/nix-darwin-24.11";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    systems.url = "github:nix-systems/default";

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

  outputs = { self, nixpkgs, darwin, ... }@inputs:
    let
      globals = {
        nixConfig = inputs.personalMonorepo + "/nix";
      };

      pkgsFor = inputs.nixpkgs.lib.genAttrs (import inputs.systems) (
        system:
          import nixpkgs {
            inherit system;
            config.allowUnfree = true;
              overlays = [
                inputs.nur.overlays.default
                inputs.agenix.overlays.default
              ];
          }
      );

      isNixosConfig = dir: builtins.pathExists (dir + "/configuration.nix");

      getConfigsForSystem = system:
        let
          # Directory path for this system
          systemDir = ./machines/${system};

          # Read directory contents
          systemDirContents = builtins.readDir systemDir;

          # Filter to only include directories
          systemDirNames = builtins.attrNames (nixpkgs.lib.filterAttrs
            (name: type: type == "directory")
            systemDirContents);

          # Filter to only include directories with configuration.nix
          systemHosts = builtins.filter (name:
            isNixosConfig (systemDir + "/${name}")
          ) systemDirNames;
        in
          systemHosts;

      aarch64DarwinHosts = getConfigsForSystem "aarch64-darwin";
      aarch64LinuxHosts = getConfigsForSystem "aarch64-linux";
      x86_64LinuxHosts = getConfigsForSystem "x86_64-linux";

      mkSystem = name: system:
        let
          systemFunction = if system == "aarch64-darwin" then darwin.lib.darwinSystem else nixpkgs.lib.nixosSystem;
          moduleType = if system == "aarch64-darwin" then "darwinModules" else "nixosModules";
          user-base = if system == "aarch64-darwin" then "/Users" else "/home";
        in
        {
        "${name}" = systemFunction {
          inherit system;

          specialArgs = {
            machine-config = (import ./machines/${system}/${name}/values.nix { pkgs = pkgsFor.${system}; }) // {user-base = user-base; hostname = name;};
            pkgs = pkgsFor.${system};
            inherit inputs globals;
          };

          modules = [
            ./machines/${system}/${name}/configuration.nix

            inputs.home-manager.${moduleType}.home-manager
            inputs.agenix.${moduleType}.default
            inputs.wsl.${moduleType}.wsl
          ];
        };
      };

      aarch64DarwinConfigs = builtins.foldl' (accumulator: name: accumulator // (mkSystem name "aarch64-darwin")) {} aarch64DarwinHosts;
      aarch64LinuxConfigs = builtins.foldl' (accumulator: name: accumulator // (mkSystem name "aarch64-linux")) {} aarch64LinuxHosts;
      x86_64LinuxConfigs = builtins.foldl' (accumulator: name: accumulator // (mkSystem name "x86_64-linux")) {} x86_64LinuxHosts;
    in {
      nixosConfigurations = aarch64LinuxConfigs // x86_64LinuxConfigs // {
        # How we build our bootstrap iso images
        iso_image_x86 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
            inputs.home-manager.nixosModules.home-manager
            ./modules/nixos/bootstrap-image.nix
          ];
        };

        iso-image-aarch64 = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = {
            machine-config = import ./machines/shared-values/bootstrap-image.nix { pkgs = pkgsFor.aarch64-linux; };
            pkgs = pkgsFor.aarch64-linux;
            inherit inputs globals;
          };
          modules = [
            (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
            inputs.home-manager.nixosModules.home-manager
            ./modules/nixos/bootstrap-image.nix
          ];
        };
      };

      darwinConfigurations = aarch64DarwinConfigs;
  };
}
