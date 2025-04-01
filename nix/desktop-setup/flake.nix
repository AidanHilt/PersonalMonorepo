{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

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

      isNixosConfig = dir: builtins.pathExists (dir + "/configuration.nix");

      aarch64LinuxDir = ./machines/aarch64-linux;
      aarch64LinuxDirContents = builtins.readDir ./machines/aarch64-linux;
      aarch64LinuxDirNames = builtins.attrNames (nixpkgs.lib.filterAttrs (name: type: type == "directory") aarch64LinuxDirContents);
      aarch64LinuxHosts = builtins.filter (name:
        isNixosConfig (aarch64LinuxDir + "/${name}")
      ) aarch64LinuxDirNames;

      mkSystem = name: system: nixpkgs.lib.nixosSystem (
        {
          inherit system;
          specialArgs = import ./machines/${system}/${name}/values.nix // { inherit inputs globals nixpkgs; };
          modules = [
            ./machines/${system}/${name}/configuration.nix
            inputs.agenix.nixosModules.default
          ];
        }
      );

      aarch64LinuxConfigs = builtins.foldl' (accumulator: name: accumulator // (mkSystem name "aarch64-linux")) {} aarch64LinuxHosts;
    in {
      nixosConfigurations = aarch64LinuxConfigs;
  };
}
