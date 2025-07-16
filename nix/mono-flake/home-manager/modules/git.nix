{ inputs, globals, pkgs, machine-config, ...}:

let 
  email = if machine-config ? git.email then machine-config.git.email else "aidanhilt2@gmail.com";
  userName = if machine-config ? git.username then machine-config.git.username else "ahilt";

in

{
  programs.git = {
    enable = true;

    userEmail = email;
    userName = userName;

    extraConfig = {
      push = {
        autoSetupRemote = true;
      }
    };
  };
}