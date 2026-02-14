{ inputs, globals, pkgs, machine-config, lib, ... }:

{
  environment.systemPackages = [];

  services.comin = {
    enable = true;
    hostname = machine-config.hostname;
    repositorySubdir = "nix/mono-flake";
    remotes = [
      {
        name = "origin";
        url = globals.personalMonorepoURL;
        branches.main.name = "master";
        branches.testing.name = globals.personalMonorepoBranch;
      }
    ];
  };
}