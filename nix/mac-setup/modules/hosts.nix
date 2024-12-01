{ inputs, pkgs, globals, config, ... }:

{
  age.secrets.rclone-config = {
    file = globals.nixConfig + "/secrets/hosts.age";
    path = "/etc/hosts";
    owner = "root";
    mode = "644";
  };

  # TODO when https://github.com/LnL7/nix-darwin/pull/939 or similar gets merged, don't just plop a hosts file
  # networking.hostFiles = [ config.age.secrets.rclone-config.path ];
}