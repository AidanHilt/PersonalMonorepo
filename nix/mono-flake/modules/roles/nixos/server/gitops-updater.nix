{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  services.comin = {
    enable = true;
    repositorySubdir = "nix/mono-flake";
    remotes = [
      {
        name = "origin";
        url = "https://github.com/AidanHilt/PersonalMonorepo";
        branches.main.name = "${globals.personalMonorepoBranch}";
      }
      {
        name = "local";
        url = "file:///tmp/PersonalMonorepo";
        branches.main.name = "HEAD";
        poller.period = 15;
      }
    ];
  };
}