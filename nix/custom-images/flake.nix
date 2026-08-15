{
  description = "Dynamic Docker images from images/ directory";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix2container }:
    let
      # Support multiple systems
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      # Helper to get pkgs for a specific system
      pkgsFor = system: import nixpkgs {
        inherit system;
      };

      nix2containerFor = system: nix2container.packages.${system}.nix2container;

      buildImagesForSystem = system:
        let
          pkgs = pkgsFor system;
          nix2containerInstance = nix2containerFor system;

          # Read all directories in ./images/
          imagesDir = ./images;
          imageDirs = builtins.attrNames (builtins.readDir imagesDir);

          # Filter to only directories
          imageNames = builtins.filter (name:
            (builtins.readDir imagesDir).${name} == "directory"
          ) imageDirs;

          # Build a docker image for each directory
          buildImageForDir = imageName:
            let
              imageDir = imagesDir + "/${imageName}";
              values = import (imageDir + "/values.nix");
              tag = values.tag or "latest";

              # Import the default.nix which should return image config
              imageConfig = import (imageDir + "/default.nix") {
                inherit pkgs;
                inherit (values) tag;
              };
            in
              nix2containerInstance.buildImage (imageConfig // {
                name = imageName;
                tag = tag;
              });

          # Create an attribute set of all images
          imagePackages = builtins.listToAttrs (
            map (name: {
              name = name;
              value = buildImageForDir name;
            }) imageNames
          );

        in imagePackages // {
          # Build all images at once
          all = pkgs.symlinkJoin {
            name = "all-docker-images";
            paths = builtins.attrValues imagePackages;
          };

          default = imagePackages.all or (builtins.head (builtins.attrValues imagePackages));
        };

    in {
      packages = forAllSystems buildImagesForSystem;
    };
}