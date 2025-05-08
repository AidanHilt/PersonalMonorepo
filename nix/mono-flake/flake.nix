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

    wsl = {
      url = "github:nix-community/NixOS-WSL";
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
      globals = {
        nixConfig = inputs.personalMonorepo + "/nix";
      };

      pkgsFor = inputs.nixpkgs.lib.genAttrs (import inputs.systems) (
        system:
          let
            nixpkgs-version = if system == "aarch64-darwin" then inputs.nixpkgs-darwin else inputs.nixpkgs;
            platform-overlays = if system == "aarch64-darwin" then [(self: super: {nodejs = super.nodejs_22;})] else [];
          in
          import nixpkgs-version {
            inherit system;
            config.allowUnfree = true;
              overlays = [
                inputs.nur.overlays.default
                inputs.agenix.overlays.default
              ] ++ platform-overlays;
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

          platformModules = if moduleType == "nixosModules" then [inputs.wsl.nixosModules.wsl] else [];
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
          ] ++ platformModules;
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
            machine-config = import ./machines/shared-values/bootstrap-image.nix;
            pkgs = pkgsFor.aarch64-linux;
            inherit inputs globals;
          };

          modules = [
            (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
            ./modules/roles/nixos/bootstrap-image.nix

            home-manager.nixosModules.home-manager {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bak";
              home-manager.extraSpecialArgs = { inherit inputs globals pkgs; };
              home-manager.users.nixos = import ./home-manager/shared-configs/server.nix {inherit inputs globals pkgs; system = pkgs.system; lib = home-manager.lib; };
            }

            (
              {pkgs, ...}: {
                isoImage = {
                  makeEfiBootable = true;
                  makeUsbBootable = true;
                  squashfsCompression = "zstd -Xcompression-level 6"; #way faster build time
                };
              }
            )
          ];
        };
      };

      darwinConfigurations = aarch64DarwinConfigs;
  };
}
