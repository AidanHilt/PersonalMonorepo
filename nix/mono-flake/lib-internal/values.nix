{ nixpkgs, darwin, inputs }:

{
  getMachineConfig = machineName: system:
    let
      machinesDir = "../machines";
      modulesDir = "../modules";

      machineValuesPath = machinesDir + "/${system}/${machineName}/values.nix";

      machineValues = import machineValuesPath;

      clusterName = machineValues.k8s.clusterName or null;

      sharedValuesPath = if clusterName != null
        then modulesDir + "/shared-values/${clusterName}.nix"
        else null;

      sharedValues = if sharedValuesPath != null && builtins.pathExists sharedValuesPath
        then import sharedValuesPath
        else {};

      sharedValues = sharedValues // {
        hostname = machineName;
      };
    in
      lib.recursiveUpdate sharedValues machineValues;
}