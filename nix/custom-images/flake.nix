{
  description = "Dynamic Docker images from images/ directory";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # Support multiple systems
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      # Helper to get pkgs for a specific system
      pkgsFor = system: import nixpkgs {
        inherit system;
      };

      buildImagesForSystem = system:
        let
          pkgs = pkgsFor system;

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
              pkgs.dockerTools.buildImage (imageConfig // {
                name = imageName;
                tag = tag;
                # Add architecture to the image config
                architecture = if system == "aarch64-linux" then "arm64"
                              else if system == "x86_64-linux" then "amd64"
                              else "amd64";
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