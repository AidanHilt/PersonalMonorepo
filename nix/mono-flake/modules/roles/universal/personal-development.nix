{ inputs, globals, pkgs, machine-config, lib, ...}:

{
imports =
  let
    scriptsDir = ../../scripts;
    entries = builtins.readDir scriptsDir;

    # only keep entries that are directories
    dirNames = builtins.filter
      (name: entries.${name} == "directory")
      (builtins.attrNames entries);

    # only keep dirs that contain a default.nix
    withDefaultNix = builtins.filter
      (name: builtins.pathExists (scriptsDir + "/${name}/default.nix"))
      dirNames;
  in
    map (name: scriptsDir + "/${name}/default.nix") withDefaultNix;

  environment.systemPackages = with pkgs; [
    act
    agenix
    syncthing
    vault
    weechat
    nss
  ];
}