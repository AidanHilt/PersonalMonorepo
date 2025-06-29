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

      defaultValuesFile = machineValues.defaultValuesFile or null;

      sharedValues = if defaultValuesFile != null && builtins.pathExists defaultValuesFile
        then import sharedValuesPath
        else {};

      defaultValues = sharedValues // {
        hostname = machineName;
        user-base = if lib.hasSuffix "darwin" system then "/Users" else "/home";
      };
    in
      lib.recursiveUpdate defaultValues machineValues;
}