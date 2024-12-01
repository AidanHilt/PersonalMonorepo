{ inputs, pkgs, globals, config, ... }:

{
  age.secrets.rclone-config = {
    file = globals.nixConfig + "/secrets/hosts.age";
    path = "/etc/hosts";
    owner = "root";
    mode = "644";
  };

  networking.hostFiles = [];
}