{ inputs, pkgs, globals, ... }:

let
  # pypkgs-build-requirements = {
  #   argparse = ["setuptools"];
  #   click = ["setuptools"];
  #   asyncio = ["setuptools"];
  #   shutils = ["setuptools"];
  # };

  # p2n-overrides = p2n.defaultPoetryOverrides.extend (self: super:
  #   builtins.mapAttrs (package: build-requirements:
  #     (builtins.getAttr package super).overridePythonAttrs (old: {
  #       buildInputs = (old.buildInputs or [ ]) ++ (builtins.map (pkg: if builtins.isString pkg then builtins.getAttr pkg super else pkg) build-requirements);
  #     })
  #   ) pypkgs-build-requirements
  # );

  # remarkable-mouse = p2n.mkPoetryApplication {
  #   projectDir =

  #   overrides = p2n-overrides;
  #   preferWheels = true;
  # };


in

{
  home = {
    packages = [
      remarkable-mouse
    ];
  };
}