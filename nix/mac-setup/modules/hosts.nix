{ inputs, pkgs, globals, config, ... }:

{
  age.secrets.rclone-config = {
    file = globals.nixConfig + "/secrets/hosts.age";
    owner = "root";
    mode = "644";
  };

  networking.extraHosts = [ config.age.secrets.rclone-config.path ];
}