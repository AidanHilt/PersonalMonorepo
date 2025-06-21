{ nixpkgs, darwin, inputs }:

let
  lib = nixpkgs.lib;

  packages = import ./packages.nix { inherit nixpkgs darwin inputs; };
in
{
  # Package management utilities
  packages = packages;

  # System discovery utilities
  discovery = {
    # Check if directory contains a NixOS/Darwin configuration
    isNixosConfig = dir: builtins.pathExists (dir + "/configuration.nix");

    # Get all machine configs for a specific system
    getConfigsForSystem = system: machinesDir:
      let
        systemDir = machinesDir + "/${system}";
        systemDirContents = builtins.readDir systemDir;
        systemDirNames = builtins.attrNames (lib.filterAttrs
          (name: type: type == "directory")
          systemDirContents
        );
        systemHosts = builtins.filter (name:
          builtins.pathExists (systemDir + "/${name}/configuration.nix")
        ) systemDirNames;
      in
      systemHosts;

    # Get all hosts for all systems
    getAllHosts = machinesDir: systems:
      lib.genAttrs systems (system:
        builtins.discovery.getConfigsForSystem system machinesDir
      );
  };

  # System building utilities
  builders = {
    # Create a system configuration
    mkSystem = { name, system, pkgsFor, machinesDir, inputs, globals ? {} }:
      let
        systemFunction = if system == "aarch64-darwin" then darwin.lib.darwinSystem else nixpkgs.lib.nixosSystem;
        moduleType = if system == "aarch64-darwin" then "darwinModules" else "nixosModules";
        user-base = if system == "aarch64-darwin" then "/Users" else "/home";

        # Platform-specific modules
        platformModules = if moduleType == "nixosModules" then [
          inputs.wsl.nixosModules.wsl
          inputs.disko.nixosModules.disko
        ] else [];

        # Load machine-specific values
        machineValuesPath = machinesDir + "/${system}/${name}/values.nix";
        machineValues = if builtins.pathExists machineValuesPath
          then import machineValuesPath { pkgs = pkgsFor.${system}; }
          else {};

        machine-config = machineValues // {
          inherit user-base;
          hostname = name;
        };
      in
      {
        "${name}" = systemFunction {
          inherit system;
          specialArgs = {
            inherit machine-config inputs globals;
            pkgs = pkgsFor.${system};
          };
          modules = [
            (machinesDir + "/${system}/${name}/configuration.nix")
            inputs.home-manager.${moduleType}.home-manager
            inputs.agenix.${moduleType}.default
          ] ++ platformModules;
        };
      };

    # Build all systems for a given architecture
    mkSystemsForArch = { system, hosts, pkgsFor, machinesDir, inputs, globals ? {} }:
      builtins.foldl' (acc: name:
        acc // (builtins.builders.mkSystem {
          inherit name system pkgsFor machinesDir inputs globals;
        })
      ) {} hosts;
  };

  # Values merging utilities (from previous artifact)
  values = {
    # Merge machine values with defaults
    mergeValues = { defaults, values ? null }:
      let
        defaultsData = if builtins.isPath defaults then import defaults else defaults;
        valuesData = if values != null then
          (if builtins.isPath values then import values else values)
        else {};
      in
      lib.recursiveUpdate defaultsData valuesData;

    # Load machine values with defaults
    loadMachineValues = { machineName, system, machinesDir, defaults ? {} }:
      let
        machineValuesPath = machinesDir + "/${system}/${machineName}/values.nix";
        hasValues = builtins.pathExists machineValuesPath;
      in
      if hasValues then
        lib.recursiveUpdate defaults (import machineValuesPath)
      else
        defaults;
  };

  # High-level configuration builders
  configs = {
    # Build all configurations for the flake
    buildAllConfigs = {
      systems,
      machinesDir,
      pkgsFor,
      inputs,
      globals ? {},
      overlays ? [],
      platformOverlays ? {}
    }:
      let
        # Get all hosts by system
        hostsBySystem = lib.genAttrs systems (system:
          discovery.getConfigsForSystem system machinesDir
        );

        # Build configurations for each system
        configsBySystem = lib.mapAttrs (system: hosts:
          builders.mkSystemsForArch {
            inherit system hosts pkgsFor machinesDir inputs globals;
          }
        ) hostsBySystem;

        # Separate Darwin and NixOS configs
        darwinSystems = lib.filter (s: lib.hasSuffix "darwin" s) systems;
        nixosSystems = lib.filter (s: !lib.hasSuffix "darwin" s) systems;

        darwinConfigs = lib.foldl' (acc: system: acc // (configsBySystem.${system} or {})) {} darwinSystems;
        nixosConfigs = lib.foldl' (acc: system: acc // (configsBySystem.${system} or {})) {} nixosSystems;
      in
      {
        nixosConfigurations = nixosConfigs;
        darwinConfigurations = darwinConfigs;
      };
  };
}