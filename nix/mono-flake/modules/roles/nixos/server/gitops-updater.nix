{
  inputs,
  globals,
  pkgs,
  machine-config,
  lib,
  ...
}:

{
  environment.systemPackages = [ ];

  services.comin = {
    enable = true;
    inherit (machine-config) hostname;
    repositorySubdir = "nix/mono-flake";
    remotes = [
      {
        name = "origin";
        url = globals.personalMonorepoURL;
        branches = {
          main.name = "master";
          testing = {
            name = globals.personalMonorepoBranch;
            operation = "switch";
          };
        };
      }
    ];
  };
}
