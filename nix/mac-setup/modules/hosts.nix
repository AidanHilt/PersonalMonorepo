{ inputs, pkgs, globals, ... }:

{
  age.secrets.rclone-config = {
    file = globals.nixConfig + "/secrets/hosts.age";
    path = "/etc/hosts";
    owner = "root";
    mode = "644";
  };

  networking.hostFiles = [ age.secrets.rclone-config.path ];
}