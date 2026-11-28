{
  inputs,
  globals,
  pkgs,
  machine-config,
  lib,
  ...
}:

let
  email = machine-config.git.email or "aidanhilt2@gmail.com";
  userName = machine-config.git.username or "ahilt";

in

{
  programs.git = {
    enable = true;

    settings = {

      user = {
        inherit email;
        name = userName;
      };

      safe = {
        directory = [ "/home/aidan/PersonalMonorepo" ];
      };

      push = {
        autoSetupRemote = true;
      };
    };
  };
}
