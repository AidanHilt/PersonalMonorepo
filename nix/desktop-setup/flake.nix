{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";

    home-manager.url = "github:nix-community/home-manager";
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

  outputs = { self, nixpkgs, ... }@inputs:
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

      aarch64LinuxHosts = getConfigsForSystem "aarch64-linux";
      x86_64LinuxHosts = getConfigsForSystem "x86_64-linux";

      mkSystem = name: system:
        let
          moduleType = if system == "aarch64-darwin" then "darwinModules" else "nixosModules";
        in
        {
        "${name}" = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { machine-config = import ./machines/${system}/${name}/values.nix; pkgs = pkgsFor.aarch64-linux; inherit inputs globals; };
          modules = [
            inputs.home-manager."${moduleType}".home-manager
            ./machines/${system}/${name}/configuration.nix
            inputs.agenix."${moduleType}".default
            inputs.wsl."${moduleType}".wsl
          ];
        };
      };

      aarch64LinuxConfigs = builtins.foldl' (accumulator: name: accumulator // (mkSystem name "aarch64-linux")) {} aarch64LinuxHosts;
      x86_64LinuxConfigs = builtins.foldl' (accumulator: name: accumulator // (mkSystem name "x86_64-linux")) {} x86_64LinuxHosts;
    in {
      nixosConfigurations = aarch64LinuxConfigs // x86_64LinuxConfigs;
  };
}
