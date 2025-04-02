{ inputs, pkgs, globals, config, ... }:

{
  age.secrets.hosts-file = {
    file = ../secrets/hosts.age;
    path = "/etc/hosts";
    owner = "root";
    mode = "644";
    # symlink = false;
  };

  # TODO when https://github.com/LnL7/nix-darwin/pull/939 or similar gets merged, don't just plop a hosts file
  # UPDATE It is merged, but uhhh, I think we need to wait for 25.05. That's ok in this case though
  # networking.hostFiles = [ config.age.secrets.rclone-config.path ];
}