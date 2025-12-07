{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  services.comin = {
    enable = true;
    remotes = [{
      name = "origin";
      url = "https://github.com/AidanHilt/PersonalMonorepo";
      branches.main.name = "${globals.personalMonorepoBranch}";
    }];
  };
}