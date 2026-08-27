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

      lib = nixpkgs.lib;

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
              tag = "${getTagForImage imageName system}-${system}";
              values = import (imageDir + "/values.nix");


              getTagForImage = imageName: system:
                let
                  hasTag = values ? tag;
                  hasVersionPackage = values ? versionPackage;

                  versionPackagePath =
                    if hasVersionPackage then lib.splitString "." values.versionPackage else null;

                  baseVersion =
                    if hasTag && hasVersionPackage then
                      throw "image ${imageName}: values.nix sets both 'tag' and 'versionPackage' — only one is allowed"
                    else if hasTag then
                      values.tag
                    else if hasVersionPackage then
                      if lib.hasAttrByPath versionPackagePath pkgs then
                        (lib.attrByPath versionPackagePath null pkgs).version
                      else
                        throw "image ${imageName}: versionPackage '${values.versionPackage}' not found in nixpkgs"
                    else
                      throw "image ${imageName}: values.nix must set either 'tag' or 'versionPackage' for ${imageName}";

                  outputTag = "${baseVersion}-${system}";
                in
                outputTag;

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