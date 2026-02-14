{ inputs, globals, pkgs, machine-config, lib, ... }:

{
  environment.systemPackages = [pkgs.neo-cowsay];

  services.comin = {
    enable = true;
    hostname = machine-config.hostname;
    debug = true;
    repositorySubdir = "nix/mono-flake";
    remotes = [
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