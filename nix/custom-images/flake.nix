{
  description = "Dynamic Docker images from images/ directory";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Read all directories in ./images/
      imagesDir = ./images;
      imageDirs = builtins.attrNames (
        builtins.readDir imagesDir
      );

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
          });

      # Create an attribute set of all images
      imagePackages = builtins.listToAttrs (
        map (name: {
          name = name;
          value = buildImageForDir name;
        }) imageNames
      );

    in {
      packages.${system} = imagePackages // {
        # Build all images at once
        all = pkgs.symlinkJoin {
          name = "all-docker-images";
          paths = builtins.attrValues imagePackages;
        };

        default = imagePackages.all or (builtins.head (builtins.attrValues imagePackages));
      };

      # Convenience outputs for loading images
      apps.${system} = builtins.mapAttrs (name: image: {
        type = "app";
        program = toString (pkgs.writeShellScript "load-${name}" ''
          echo "Loading ${name} image..."
          docker load < ${image}
          echo "Image ${name} loaded successfully!"
        '');
      }) imagePackages;
    };
}