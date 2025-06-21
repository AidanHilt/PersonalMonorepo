{ nixpkgs, darwin, inputs }:

let
  lib = nixpkgs.lib;

  buildersLib = import ./builders.nix { inherit nixpkgs darwin inputs; };
  configLib = import ./configs.nix { inherit nixpkgs darwin inputs; };
  discoveryLib = import ./discovery.nix { inherit nixpkgs darwin inputs; };
  packagesLib = import ./packages.nix { inherit nixpkgs darwin inputs; };
  valuesLib = import ./values.nix { inherit nixpkgs darwin inputs; };
in
{
  # Package management utilities
  packages = packagesLib;

  # System discovery utilities
  discovery = discoveryLib;

  # System building utilities
  builders = buildersLib;

  # Values merging utilities (from previous artifact)
  values = valuesLib;

  # High-level configuration builders
  configs = configsLib;
}