{ nixpkgs, darwin, inputs }:

{
  getMachineConfig = machineName: system:
    let
      machinesDir = "../machines";
      modulesDir = "../modules";

      machineValuesPath = machinesDir + "/${system}/${machineName}/values.nix";

      machineValues = import machineValuesPath;

      clusterName = machineValues.defaultValues or null;

      sharedValuesPath = if clusterName != null
        then modulesDir + "/shared-values/${defaultValues}.nix"
        else null;

      sharedValues = if sharedValuesPath != null && builtins.pathExists sharedValuesPath
        then import sharedValuesPath
        else {};

      defaultValues = sharedValues // {
        hostname = machineName;
      };
    in
      lib.recursiveUpdate defaultValues machineValues;
}