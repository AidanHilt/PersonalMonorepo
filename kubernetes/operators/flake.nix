{
  description = ''
    Discovers every operator under ./operators, and for each one produces a
    Go binary, generated CRDs, generated RBAC, a container image, and a
    fully valid Helm chart — with zero per-operator Nix code required.
    Adding a new operator means adding a directory; nothing here changes.
  '';

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nix2container,
    }:
    # Cross-system support was flagged as an open item in the spec but
    # explicitly requested ("please support x86_64- and aarch64-linux for
    # our systems") — implemented here via flake-utils rather than a single
    # hard-coded `system`.
    #
    # recursiveUpdate merges that Linux-only output with a second,
    # wider-system one (below) that only ever adds `skopeo-nix2container`:
    # a host-native copy of nix2container's skopeo fork, which understands
    # the `nix:` transport over a locally-built image's JSON output. It
    # exists so a non-Linux host (e.g. this flake's macOS dev-loop caller)
    # can copy a Linux-built operator image out of the Nix store without
    # needing to execute any Linux-built binary itself.
    nixpkgs.lib.recursiveUpdate
      (flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          inherit (pkgs) lib;
          n2c = nix2container.packages.${system}.nix2container;

          # go.mod presence is deliberately the *only* signal used to mark a
          # directory as an operator — no separate marker file that can drift
          # out of sync with reality.
          isOperatorDir =
            name: type: type == "directory" && builtins.pathExists (./operators + "/${name}/go.mod");

          operatorNames = builtins.attrNames (lib.filterAttrs isOperatorDir (builtins.readDir ./operators));

          mkOperator =
            name:
            import ./nix/mk-operator.nix {
              inherit
                pkgs
                lib
                n2c
                self
                name
                ;
              src = ./operators + "/${name}";
            };

          operators = lib.genAttrs operatorNames mkOperator;

          perOperatorPackages = lib.foldl' (
            acc: name:
            acc
            // {
              "${name}-binary" = operators.${name}.binary;
              "${name}-crds" = operators.${name}.crds;
              "${name}-rbac" = operators.${name}.rbac;
              "${name}-image" = operators.${name}.image;
              "${name}-chart" = operators.${name}.chart;
            }
          ) { } operatorNames;

          # One `go vet` check per operator, derived from the same operator
          # list as the packages — so a new operator directory is checked
          # without any change here. The derivation itself lives in
          # `nix/mk-operator.nix` ("3b. go vet"), because it needs the
          # `binary` derivation's vendored module graph.
          perOperatorChecks = lib.foldl' (
            acc: name:
            acc
            // {
              "${name}-vet" = operators.${name}.vet;
            }
          ) { } operatorNames;

          # statix over the whole flake source tree, not just the files a
          # change happens to touch. Every `.nix` file in this tree is a
          # standalone, parseable Nix file (`flake.nix`,
          # `nix/mk-operator.nix`, and each operator's `vendor-hash.nix`), so
          # unlike nix/mono-flake's equivalent fixture this one needs no
          # `--ignore`.
          statixCheck =
            pkgs.runCommand "statix-check"
              {
                nativeBuildInputs = [ pkgs.statix ];
              }
              ''
                cd ${./.}
                statix check .
                touch $out
              '';

          # An empty-output marker derivation: the real work happens in
          # buildInputs, so `nix build .#checks.<system>.agent-validate`
          # builds — and therefore validates — every per-operator package,
          # every per-operator `go vet` check, and statix. `default` (the
          # image+chart linkFarm) is deliberately NOT a build input: it only
          # links outputs already covered above, so including it would add no
          # coverage. The graph stays lazy and acyclic — nothing above ever
          # references `checks` or this aggregate.
          #
          # That ATTRIBUTE name is fixed by agent-validate's flake contract and
          # must stay `agent-validate`. The derivation it points at is
          # deliberately named `aggregate-check` instead, so it is never
          # confused with the `agent-validate` SCRIPT package from the
          # nix/scripts flake (the same convention as nix/mono-flake,
          # nix/scripts, and nix/agentic-ai-stack).
          aggregateCheck =
            pkgs.runCommand "aggregate-check"
              {
                buildInputs =
                  builtins.attrValues perOperatorPackages ++ builtins.attrValues perOperatorChecks ++ [ statixCheck ];
              }
              ''
                touch $out
              '';
        in
        {
          packages = perOperatorPackages // {
            # Convenience aggregate: `nix build` with no target builds every
            # operator's image + chart in one go.
            default = pkgs.linkFarm "all-operators" (
              lib.concatMap (name: [
                {
                  name = "${name}-image";
                  path = operators.${name}.image;
                }
                {
                  name = "${name}-chart";
                  path = operators.${name}.chart;
                }
              ]) operatorNames
            );
          };

          # `checks.<system>` for the Linux systems this flake actually builds
          # packages for: the contract agent-validate preflights (see the
          # aggregateCheck comment above). See IMPLEMENTERS.md "Checks" for the
          # Linux/darwin split.
          checks = perOperatorChecks // {
            statix = statixCheck;
            agent-validate = aggregateCheck;
          };
        }
      ))
      (
        flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ] (
          system:
          let
            pkgs = import nixpkgs { inherit system; };

            # Darwin tier of `checks.<system>`: the same statix fixture shape
            # as the Linux tier above, built from this system's own pkgs, plus
            # an aggregate whose ONLY build input is that fixture. Nothing
            # from the Linux package set (`binary`/`crds`/`rbac`/`image`/
            # `chart`) or its `go vet` checks may appear here — those
            # derivations are Linux-only, so referencing them here would make
            # this system's `checks` unbuildable. statix alone is what makes
            # agent-validate's currentSystem preflight satisfiable on a darwin
            # host; see IMPLEMENTERS.md "Checks".
            statixCheck =
              pkgs.runCommand "statix-check"
                {
                  nativeBuildInputs = [ pkgs.statix ];
                }
                ''
                  cd ${./.}
                  statix check .
                  touch $out
                '';

            aggregateCheck =
              pkgs.runCommand "aggregate-check"
                {
                  buildInputs = [ statixCheck ];
                }
                ''
                  touch $out
                '';
          in
          {
            packages.skopeo-nix2container = nix2container.packages.${system}.skopeo-nix2container;
          }
          # This eachSystem list also covers both Linux systems, which already
          # get their own (fuller) `checks` from the Linux block above.
          # recursiveUpdate gives the second argument precedence, so emitting
          # the darwin tier for them here would silently replace the Linux
          # `agent-validate` aggregate with this statix-only one — hence the
          # gate.
          // nixpkgs.lib.optionalAttrs (nixpkgs.lib.hasSuffix "-darwin" system) {
            checks = {
              statix = statixCheck;
              agent-validate = aggregateCheck;
            };
          }
        )
      );
}
