{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports =
    let
      scriptsDir = ../../scripts;
      entries = builtins.readDir scriptsDir;
      dirNames = builtins.filter
        (name: entries.${name} == "directory")
        (builtins.attrNames entries);
      candidatePaths = map
        (name: scriptsDir + "/${name}/default.nix")
        dirNames;
    in
      builtins.filter builtins.pathExists candidatePaths;

  environment.systemPackages = with pkgs; [
    act
    agenix
    cocogitto
    nss
    syncthing
    vault
    weechat
  ];
}