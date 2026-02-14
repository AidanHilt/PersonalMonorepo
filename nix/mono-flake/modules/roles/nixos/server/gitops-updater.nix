{ inputs, globals, pkgs, machine-config, lib, ... }:

{
  environment.systemPackages = [];

  services.comin = {
    enable = true;
    hostname = machine-config.hostname;
    debug = true;
    repositorySubdir = "nix/mono-flake";
    remotes = [
      # Test
      {
        name = "origin";
        url = globals.personalMonorepoURL;
        branches.main.name = "master";
        branches.testing.name = globals.personalMonorepoBranch;
        branches.testing.operation = "switch";
      }
    ];
  };
}