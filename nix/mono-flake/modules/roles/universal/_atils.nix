{ inputs, globals, pkgs, machine-config, machineDir, ...}:

let
  util = inputs.pyproject-nix.build.util;

  homeDir = "${machine-config.userBase}/${machine-config.username}";

  workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = globals.nixConfig + "/../atils";};

  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };

  overrides = pkgs.lib.composeExtensions (inputs.uv2nix_hammer_overrides.overrides pkgs)(
    final: prev: {}
  );

  pythonSet =
    (pkgs.callPackage inputs.pyproject-nix.build.packages { python = pkgs.python312; })
    .overrideScope (pkgs.lib.composeManyExtensions [
      inputs.pyproject-build-systems.overlays.default
      overlay
      overrides
    ]);

  projectNameInToml = "atils";
  thisProjectAsNixPkg = pythonSet.${projectNameInToml};

  appPythonEnv = pythonSet.mkVirtualEnv
    (thisProjectAsNixPkg.pname + "-env")
    workspace.deps.default;

  atils = util.mkApplication {
    venv = appPythonEnv;
    package = thisProjectAsNixPkg;
  };
in

{
  environment.systemPackages = [
    thisProjectAsNixPkg
  ];

  environment.variables = {
    ATILS_INSTALL_DIR="${homeDir}/PersonalMonorepo";
    ATILS_KUBECONFIG_LOCATION="${homeDir}/.kube/";
    ATILS_SCRIPT_INSTALL_DIRECTORY="${homeDir}/PersonalMonorepo/atils";
    ATILS_HELM_CHARTS_DIR="kubernetes/helm-charts";
    ATILS_LOG_LEVEL="INFO";
    ATILS_JOBS_DIR="kubernetes/jobs";
    ATILS_CONFIG_DIRECTORY="${homeDir}/.atils";
  };
}
