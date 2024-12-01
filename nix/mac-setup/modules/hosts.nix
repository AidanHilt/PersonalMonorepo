{ inputs, pkgs, globals, config, ... }:

{
  age.secrets.hosts = {
    file = globals.nixConfig + "/secrets/hosts.age";
    # owner = "root";
    # mode = "644";
    # symlink = false;
  };

  # TODO when https://github.com/LnL7/nix-darwin/pull/939 or similar gets merged, don't just plop a hosts file
  # networking.hostFiles = [ config.age.secrets.rclone-config.path ];
}