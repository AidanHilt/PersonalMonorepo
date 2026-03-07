{ nixpkgs, darwin, inputs }:

let
  lib = nixpkgs.lib;
in

{
  getMachineConfig = machineName: system:
    let
      machinesDir = ../machines;
      modulesDir = ../modules;

      machineValuesPath = machinesDir + "/${system}/${machineName}/values.nix";

      machineValues = import machineValuesPath;

      defaultValuesFile = machineValues.defaultValues or null;

      sharedValuesPath = if defaultValuesFile != null
        then modulesDir + "/shared-values/${defaultValuesFile}.nix"
        else null;

      sharedValues = if sharedValuesPath != null && builtins.pathExists sharedValuesPath
        then import sharedValuesPath
        else {};

      defaultValues = sharedValues // {
        hostname = machineName;
        userBase = if lib.hasSuffix "darwin" system then "/Users" else "/home";
      };
    in
      lib.recursiveUpdate defaultValues machineValues;
}