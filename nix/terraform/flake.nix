{
  description = "Terranix infrastructure generator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    terranix = {
      url = "github:terranix/terranix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    personalMonorepo = {
      url = "github:aidanhilt/PersonalMonorepo/project-appocalypse/knative-function-operator";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      terranix,
      ...
    }@inputs:
    let
      system = "aarch64-linux";
      # Second tier for checks only -- see the "checks" comment below. Nothing
      # in `packages` is ever built for or from this system.
      darwinSystem = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      darwinPkgs = nixpkgs.legacyPackages.${darwinSystem};
      inherit (nixpkgs) lib;

      libFiles = builtins.attrNames (
        lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name) (
          builtins.readDir ./lib
        )
      );

      loadLib = file: import ./lib/${file} { inherit lib pkgs inputs; };

      libFunctions = builtins.foldl' (acc: file: acc // (loadLib file)) { } libFiles;

      moduleNames = builtins.attrNames (
        pkgs.lib.filterAttrs (
          name: type: type == "directory" && builtins.pathExists ./modules/${name}/infra.nix
        ) (builtins.readDir ./modules)
      );

      buildModule =
        name:
        terranix.lib.terranixConfiguration {
          inherit system;
          modules = [ ./modules/${name}/infra.nix ];
          extraArgs = {
            inherit
              libFunctions
              lib
              inputs
              pkgs
              ;
          };
        };

      modulePackages = builtins.listToAttrs (
        map (name: {
          inherit name;
          value = buildModule name;
        }) moduleNames
      );

      # ---- checks -------------------------------------------------------
      # `checks.<system>.agent-validate` is the attribute name agent-validate's
      # flake contract requires for any path at or below this flake's root; the
      # derivation it points at is deliberately named `aggregate-check` (same
      # convention as nix/mono-flake, nix/scripts and nix/agentic-ai-stack) so
      # it is never confused with the `agent-validate` script package from the
      # scripts flake. See the "Checks" section of IMPLEMENTERS.md.
      #
      # statix over every Nix source in this flake, not just the files a change
      # happens to touch. Same shape as nix/mono-flake/flake.nix's fixture;
      # there is no `templates/`-style exclusion to make here because every
      # `.nix` file in this directory is standalone valid Nix.
      mkStatixCheck =
        statixPkgs:
        statixPkgs.runCommand "statix-check"
          {
            nativeBuildInputs = [ statixPkgs.statix ];
          }
          ''
            cd ${./.}
            statix check .
            touch $out
          '';

      statixCheck = mkStatixCheck pkgs;
      darwinStatixCheck = mkStatixCheck darwinPkgs;

      # An empty-output marker derivation: the real work happens in
      # buildInputs, so `nix build .#checks.<system>.agent-validate` builds
      # (and therefore validates) everything that tier covers. The graph stays
      # lazy and acyclic -- neither statix check nor `modulePackages` ever
      # references `checks` or an aggregate.
      #
      # Two tiers, because everything this flake packages is aarch64-linux-only
      # while agent-validate preflights `checks.<currentSystem>.agent-validate`
      # on whatever host it runs on:
      #
      # - aarch64-linux is the full check set: every module package (building
      #   one forces that module's complete terranix evaluation, helm-value
      #   `loadMergedValues` IFD included) plus statix.
      # - aarch64-darwin is a runnable subset -- statix only -- that exists so
      #   the currentSystem preflight succeeds on a Darwin host. Its aggregate
      #   must never reference a module package or anything else from the
      #   aarch64-linux package set: such a dependency would make it both
      #   unbuildable and (because the modules evaluate Helm values through
      #   IFD) unevaluatable locally.
      aggregateCheck =
        pkgs.runCommand "aggregate-check"
          {
            buildInputs = builtins.attrValues modulePackages ++ [ statixCheck ];
          }
          ''
            touch $out
          '';

      darwinAggregateCheck =
        darwinPkgs.runCommand "aggregate-check"
          {
            buildInputs = [ darwinStatixCheck ];
          }
          ''
            touch $out
          '';

    in
    {
      packages.${system} = modulePackages;

      checks = {
        ${system} = {
          statix = statixCheck;
          agent-validate = aggregateCheck;
        };

        ${darwinSystem} = {
          statix = darwinStatixCheck;
          agent-validate = darwinAggregateCheck;
        };
      };
    };
}
