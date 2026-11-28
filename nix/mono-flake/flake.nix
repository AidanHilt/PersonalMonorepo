{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
    };

    nur.url = "github:nix-community/nur";

    personalMonorepo = {
      url = "github:aidanhilt/PersonalMonorepo/project-appocalypse/knative-function-operator";
      flake = false;
    };

    scripts = {
      url = "github:aidanhilt/PersonalMonorepo/project-appocalypse/knative-function-operator?dir=nix/scripts";
    };

    comin = {
      url = "github:nlewo/comin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    systems.url = "github:nix-systems/default";

    # Home Manager items
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Linux-specific items
    wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-lima = {
      url = "github:nixos-lima/nixos-lima/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/01ef07c1c8bc8d9db9c0c9c59a8fea701b7f5a34";

    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Darwin-specific items
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-26.05-darwin";

    darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      darwin,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;

      internalLib = import ./lib-internal/default.nix { inherit nixpkgs darwin inputs; };

      globals = {
        nixConfig = inputs.personalMonorepo + "/nix";
        personalMonorepoBranch = "main";
        personalMonorepoURL = "https://github.com/AidanHilt/PersonalMonorepo";
      };

      allSystems = import inputs.systems;
      systems = nixpkgs.lib.filter (sys: builtins.pathExists (./machines + "/${sys}")) allSystems;

      # The single place new, extra (unoverlaid) package sets are declared.
      # Each entry gets built for every system and threaded into specialArgs
      # (and home-manager's extraSpecialArgs) as `pkgs-<name>` -- see
      # lib-internal/packages.nix's genExtraPkgsFor and lib-internal/builders.nix.
      extraPkgsInputs = {
        unstable = inputs.nixpkgs-unstable;
      };

      baseOverlays = [
        inputs.nur.overlays.default
        inputs.agenix.overlays.default
        inputs.nix-vscode-extensions.overlays.default
        inputs.nix-cachyos-kernel.overlays.default
      ];

      platformOverlays = {
        "aarch64-darwin" = [
          (self: super: { nodejs = super.nodejs_22; })
        ];
      };

      pkgsFor = internalLib.packages.genPkgsFor inputs.systems baseOverlays platformOverlays;
      extraPkgsFor = internalLib.packages.genExtraPkgsFor inputs.systems extraPkgsInputs;

      allConfigs = internalLib.configs.buildAllConfigs {
        inherit
          systems
          pkgsFor
          extraPkgsFor
          inputs
          globals
          ;
        machinesDir = ./machines;
        overlays = baseOverlays;
        inherit platformOverlays;
      };

      # ---- checks -------------------------------------------------------
      # `checks.<system>.agent-validate` is the attribute name agent-validate's
      # flake contract requires for any path at or below this flake's root; the
      # derivation it points at is deliberately named `aggregate-check` (same
      # convention as nix/scripts and nix/agentic-ai-stack) so it is never
      # confused with the `agent-validate` script package from the scripts
      # flake. See the "Checks" section of IMPLEMENTERS.md.

      # Every host this flake defines, NixOS and Darwin alike, keyed by
      # hostname. Reading `config.system.build.toplevel.name` for each one is
      # what forces that host's complete module evaluation (option fixpoint,
      # every imported module, every package reference), so a host that cannot
      # evaluate fails the `host-evaluation` check below. A derivation's `name`
      # is a plain string, not a store path, so this report carries no build
      # dependency on any toplevel output: this check evaluates every host, it
      # never builds one.
      hostReport = builtins.toJSON (
        lib.mapAttrs (_hostname: hostConfig: hostConfig.config.system.build.toplevel.name) (
          allConfigs.nixosConfigurations // allConfigs.darwinConfigurations
        )
      );

      mkChecksForSystem =
        system:
        let
          pkgs = pkgsFor.${system};

          # Explicit fixtures, each independently buildable
          # (`nix build .#checks.<system>.<name>`) -- no marker-file
          # test-discovery framework. Every check the aggregate covers is
          # named here.
          fixtureChecks = {
            # All-host evaluation, never a fleet build: the report is computed
            # at evaluation time from `hostReport` above, so this derivation's
            # only job is to write it out once every host evaluated. The output
            # is a DIRECTORY containing the report, not the report itself: a
            # file-valued build input is sourced by stdenv as a setup hook, and
            # this file is JSON, not shell.
            host-evaluation = pkgs.runCommand "host-evaluation" { } ''
              mkdir -p $out
              echo ${lib.escapeShellArg hostReport} > $out/hosts.json
            '';

            # statix over the whole mono-flake Nix source tree, not just the
            # files a given change happens to touch. `templates/` is excluded:
            # those files are scaffolding with intentional `{{placeholder}}`
            # syntax, so they are not standalone valid Nix and statix cannot
            # parse them.
            statix =
              pkgs.runCommand "statix-check"
                {
                  nativeBuildInputs = [ pkgs.statix ];
                }
                ''
                  cd ${./.}
                  statix check --ignore 'templates/*' .
                  touch $out
                '';

            # `darwin-install.sh` has no other automated coverage. It is a zsh
            # script and shellcheck has no zsh dialect, so this checks it in
            # bash dialect at error severity only, excluding the codes that are
            # artifacts of the zsh-only syntax it actually uses (`${(f)...}`
            # splitting, `"$array[@]"` loops, `${array[@]:0:1}`): SC2296,
            # SC2066, SC1087. Style/warning-level bash advice is deliberately
            # not enforced -- that would mean rewriting the script for bash
            # (see IMPROVEMENTS.md).
            darwin-install-sh =
              pkgs.runCommand "darwin-install-sh-check"
                {
                  nativeBuildInputs = [
                    pkgs.bash
                    pkgs.shellcheck
                  ];
                }
                ''
                  bash -n ${./darwin-install.sh}
                  shellcheck --shell=bash --severity=error --exclude=SC2296,SC2066,SC1087 ${./darwin-install.sh}
                  touch $out
                '';

            # helmfmt is not in nixpkgs and is consumed via `callPackage`
            # rather than an overlay (see packages/helmfmt.nix), so nothing
            # else in this flake would realize it. Its per-system release
            # tarball hashes are only checked when the package is actually
            # fetched, which is what this fixture does.
            helmfmt = pkgs.callPackage ./packages/helmfmt.nix { };
          };

          # An empty-output marker derivation: the real work happens in
          # buildInputs, so `nix build .#checks.<system>.agent-validate` builds
          # (and therefore validates) every fixture above. The graph stays lazy
          # and acyclic -- fixtureChecks never reference `checks` or this
          # aggregate.
          aggregateCheck =
            pkgs.runCommand "aggregate-check"
              {
                buildInputs = builtins.attrValues fixtureChecks;
              }
              ''
                touch $out
              '';
        in
        fixtureChecks // { agent-validate = aggregateCheck; };

    in
    {
      inherit (allConfigs) darwinConfigurations nixosConfigurations;

      checks = lib.genAttrs systems mkChecksForSystem;
    };
}
