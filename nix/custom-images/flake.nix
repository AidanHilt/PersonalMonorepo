{
  description = "Dynamic Docker images from images/ directory";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nix2container,
    }:
    let
      # Support multiple systems
      #
      # Images are Linux-only: nix2container targets Linux, and the packages
      # the images embed (it-tools, transmission) are not available on
      # darwin. These are also the only systems that get image `packages`.
      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # darwin gets a `checks`-only tier (see `buildDarwinChecksForSystem`):
      # there are no images to build there, but agent-validate's flake
      # contract is keyed on `builtins.currentSystem`, so a darwin host still
      # needs `checks.<system>.agent-validate` to exist -- otherwise
      # agent-validate exits 24 for any path below this flake's root before
      # running a single check.
      darwinSystems = [
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      systems = linuxSystems ++ darwinSystems;

      inherit (nixpkgs) lib;

      forAllLinuxSystems = nixpkgs.lib.genAttrs linuxSystems;

      # Helper to get pkgs for a specific system
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
        };

      nix2containerFor = system: nix2container.packages.${system}.nix2container;

      # Everything one system exposes: its image packages, plus this flake's
      # checks (see `aggregateCheck`). Kept as a single builder so `checks`
      # can reference the very same image packages `packages` exposes.
      buildOutputsForSystem =
        system:
        let
          pkgs = pkgsFor system;
          nix2containerInstance = nix2containerFor system;

          # Read all directories in ./images/
          imagesDir = ./images;
          imageDirs = builtins.attrNames (builtins.readDir imagesDir);

          # Filter to only directories
          imageNames = builtins.filter (name: (builtins.readDir imagesDir).${name} == "directory") imageDirs;

          # Build a docker image for each directory
          buildImageForDir =
            imageName:
            let
              imageDir = imagesDir + "/${imageName}";
              tag = "${getTagForImage imageName system}";
              values = import (imageDir + "/values.nix");

              getTagForImage =
                imageName: system:
                let
                  hasTag = values ? tag;
                  hasVersionPackage = values ? versionPackage;

                  versionPackagePath = if hasVersionPackage then lib.splitString "." values.versionPackage else null;

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

              fullImageName = "ghcr.io/aidanhilt/${imageName}";
            in
            nix2containerInstance.buildImage (
              imageConfig
              // {
                name = fullImageName;
                inherit tag;
              }
            )
            // {
              imageTag = tag;
              imageName = fullImageName;
            };

          # Create an attribute set of all images
          imagePackages = builtins.listToAttrs (
            map (name: {
              inherit name;
              value = buildImageForDir name;
            }) imageNames
          );

          # statix over the whole flake Nix source tree, not just the files a
          # change happens to touch: `flake.nix` plus every
          # `images/*/default.nix` and `images/*/values.nix`.
          statix =
            pkgs.runCommand "statix-check"
              {
                nativeBuildInputs = [ pkgs.statix ];
              }
              ''
                cd ${./.}
                statix check .
                touch $out
              '';

          # This flake's `checks.<system>.agent-validate` aggregate: an
          # empty-output marker derivation whose real work happens in
          # buildInputs, so `nix build .#checks.<system>.agent-validate`
          # performs a REAL nix2container build of every image (not just an
          # evaluation) and runs `statix`. Deliberately heavier than a
          # lint-only check: this is the only automated proof that every
          # image in `images/` still builds.
          #
          # That ATTRIBUTE name is fixed by the contract and must stay
          # `agent-validate`. The derivation it points at is deliberately
          # named `aggregate-check` instead, so it is never confused with the
          # `agent-validate` SCRIPT package from the `nix/scripts` flake --
          # the same convention as nix/mono-flake, nix/scripts and
          # nix/agentic-ai-stack. The graph stays lazy and acyclic: neither
          # fixture references `checks` or this aggregate.
          #
          # `all`/`default` are excluded on purpose: they are `symlinkJoin`s
          # of the per-image packages already listed here.
          aggregateCheck =
            pkgs.runCommand "aggregate-check"
              {
                buildInputs = builtins.attrValues imagePackages ++ [ statix ];
              }
              ''
                touch $out
              '';
        in
        {
          packages = imagePackages // {
            # Build all images at once
            all = pkgs.symlinkJoin {
              name = "all-docker-images";
              paths = builtins.attrValues imagePackages;
            };

            default = imagePackages.all or (builtins.head (builtins.attrValues imagePackages));
          };

          checks = {
            inherit statix;
            agent-validate = aggregateCheck;
          };
        };

      # The darwin `checks` tier: statix and nothing else. Reference no image
      # package here -- none of them can be built on darwin (see
      # `linuxSystems`), and this tier has to stay runnable on a plain macOS
      # host so `agent-validate` can actually validate a change to this flake
      # from one.
      buildDarwinChecksForSystem =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          statix =
            pkgs.runCommand "statix-check"
              {
                nativeBuildInputs = [ pkgs.statix ];
              }
              ''
                cd ${./.}
                statix check .
                touch $out
              '';

          # Same empty-marker convention as the Linux tier and
          # nix/mono-flake: the attribute is `agent-validate`, the derivation
          # it points at is `aggregate-check`.
          aggregateCheck =
            pkgs.runCommand "aggregate-check"
              {
                buildInputs = [ statix ];
              }
              ''
                touch $out
              '';
        in
        {
          inherit statix;
          agent-validate = aggregateCheck;
        };

    in
    {
      packages = forAllLinuxSystems (system: (buildOutputsForSystem system).packages);

      checks = nixpkgs.lib.genAttrs systems (
        system:
        if builtins.elem system linuxSystems then
          (buildOutputsForSystem system).checks
        else
          buildDarwinChecksForSystem system
      );
    };
}
