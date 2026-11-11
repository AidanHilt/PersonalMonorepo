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

  outputs = { self, nixpkgs, flake-utils, nix2container }:
    # Cross-system support was flagged as an open item in the spec but
    # explicitly requested ("please support x86_64- and aarch64-linux for
    # our systems") — implemented here via flake-utils rather than a single
    # hard-coded `system`.
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;
        n2c = nix2container.packages.${system}.nix2container;

        # go.mod presence is deliberately the *only* signal used to mark a
        # directory as an operator — no separate marker file that can drift
        # out of sync with reality.
        isOperatorDir = name: type:
          type == "directory"
          && builtins.pathExists (./operators + "/${name}/go.mod");

        operatorNames = builtins.attrNames (
          lib.filterAttrs isOperatorDir (builtins.readDir ./operators)
        );

        mkOperator = name: import ./nix/mk-operator.nix {
          inherit pkgs lib n2c self;
          name = name;
          src = ./operators + "/${name}";
        };

        operators = lib.genAttrs operatorNames mkOperator;

        perOperatorPackages = lib.foldl' (acc: name: acc // {
          "${name}-binary" = operators.${name}.binary;
          "${name}-crds" = operators.${name}.crds;
          "${name}-rbac" = operators.${name}.rbac;
          "${name}-image" = operators.${name}.image;
          "${name}-chart" = operators.${name}.chart;
        }) { } operatorNames;
      in
      {
        packages = perOperatorPackages // {
          # Convenience aggregate: `nix build` with no target builds every
          # operator's image + chart in one go.
          default = pkgs.linkFarm "all-operators" (
            lib.concatMap
              (name: [
                { name = "${name}-image"; path = operators.${name}.image; }
                { name = "${name}-chart"; path = operators.${name}.chart; }
              ])
              operatorNames
          );
        };
      }
    );
}
