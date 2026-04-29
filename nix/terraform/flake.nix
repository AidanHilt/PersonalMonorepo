{
  description = "Terranix infrastructure generator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    terranix = {
      url = "github:terranix/terranix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, terranix, ... }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      moduleNames = builtins.attrNames (
        pkgs.lib.filterAttrs
          (name: type:
            type == "directory" &&
            builtins.pathExists ./modules/${name}/infra.nix
          )
          (builtins.readDir ./modules)
      );

      buildModule = name: terranix.lib.terranixConfiguration {
        inherit system;
        modules = [ ./modules/${name}/infra.nix ];
      };

    in {
      packages.${system} = builtins.listToAttrs (
        map (name: {
          inherit name;
          value = buildModule name;
        }) moduleNames
      );
    };
}