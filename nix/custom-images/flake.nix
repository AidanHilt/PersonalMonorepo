{
  description = "Docker images built with nix for smaller size and greater security";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }@inputs:
    let
      # Support multiple systems
      systems = [ "x86_64-linux" "aarch64-linux" ];

      forAllSystems = nixpkgs.lib.genAttrs systems;
      libPackages = import ./lib/packages.nix { inherit nixpkgs inputs; };

      buildImagesForSystem = system:
        let
          pkgs = libPackages.genMuslPkgs system;

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
                inherit inputs;
              };
            in
              pkgs.dockerTools.buildLayeredImage (imageConfig // {
                #maxLayers = 5;
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