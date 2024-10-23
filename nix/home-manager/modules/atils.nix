{ inputs, pkgs, globals, ... }:

let
  p2n = (inputs.poetry2nix.lib.mkPoetry2Nix { inherit pkgs; });

  pypkgs-build-requirements = {
    argparse = ["setuptools"];
    click = ["setuptools"];
    asyncio = ["setuptools"];
    shutils = ["setuptools"];
  };

  p2n-overrides = p2n.defaultPoetryOverrides.extend (self: super:
    builtins.mapAttrs (package: build-requirements:
      (builtins.getAttr package super).overridePythonAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ (builtins.map (pkg: if builtins.isString pkg then builtins.getAttr pkg super else pkg) build-requirements);
      })
    ) pypkgs-build-requirements
  );

  atils = p2n.mkPoetryApplication {
    projectDir = globals.personalConfig + "/../atils";

    overrides = p2n-overrides;
    preferWheels = true;
  };
in

{
  home = {
    packages = [
      atils
    ];

    sessionVariables = {
      ATILS_INSTALL_DIR="/Users/ahilt/PersonalMonorepo";
      ATILS_KUBECONFIG_LOCATION="/Users/ahilt/.kube/";
      ATILS_SCRIPT_INSTALL_DIRECTORY="/Users/ahilt/PersonalMonorepo/atils";
      ATILS_HELM_CHARTS_DIR="kubernetes/helm-charts";
      ATILS_LOG_LEVEL="INFO";
      ATILS_JOBS_DIR="kubernetes/jobs";
      ATILS_CONFIG_DIRECTORY="/Users/ahilt/.atils";
    };
  };
}