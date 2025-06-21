{ nixpkgs, darwin, inputs }:

let
  lib = nixpkgs.lib;

  builders = import ./builders.nix { inherit nixpkgs darwin inputs; };
  discovery = import ./discovery.nix { inherit nixpkgs darwin inputs; };
in

{
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
        if builtins.pathExists (machinesDir + "/${system}")
        then discovery.getConfigsForSystem system machinesDir
        else {}
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
}