{ nixpkgs, darwin, inputs }:

let
  lib = nixpkgs.lib;
in

{
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
}