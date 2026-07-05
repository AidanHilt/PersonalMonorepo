{
  description = "Terranix infrastructure generator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    terranix = {
      url = "github:terranix/terranix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    personalMonorepo = {
      url = "github:aidanhilt/PersonalMonorepo/project-rockhard/user-mgmt";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, terranix, ... }@inputs:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      libFiles = builtins.attrNames (
        lib.filterAttrs (name: type:
          type == "regular" && lib.hasSuffix ".nix" name
        ) (builtins.readDir ./lib)
      );

      loadLib = file: import ./lib/${file} { inherit lib pkgs inputs; };

      libFunctions = builtins.foldl' (acc: file:
          acc // (loadLib file)
        ) {} libFiles;

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
        extraArgs = {inherit libFunctions lib inputs pkgs;};
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