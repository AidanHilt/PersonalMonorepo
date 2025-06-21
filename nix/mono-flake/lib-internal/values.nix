{ nixpkgs, darwin, inputs }:

{
  # Merge machine values with defaults
  mergeValues = { defaults, values ? null }:
    let
      defaultsData = if builtins.isPath defaults then import defaults else defaults;
      valuesData = if values != null then
        (if builtins.isPath values then import values else values)
      else {};
    in
    lib.recursiveUpdate defaultsData valuesData;

  # Load machine values with defaults
  loadMachineValues = { machineName, system, machinesDir, defaults ? {} }:
    let
      machineValuesPath = machinesDir + "/${system}/${machineName}/values.nix";
      hasValues = builtins.pathExists machineValuesPath;
    in
    if hasValues then
      lib.recursiveUpdate defaults (import machineValuesPath)
    else
      defaults;
  }