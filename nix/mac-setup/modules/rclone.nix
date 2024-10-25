{ inputs, pkgs, globals, ... }:

{

  environment.systemPackages = [
    pkgs.rclone
  ];

  # TODO update this so we encrypt files in Google Drive, for extra oomph
  age.secrets.rclone-config = {
    file = ../secrets/rclone-config.age;
    path = "/Users/${globals.username}/.config/rclone/rclone.conf";
    owner = "${globals.username}";
    group = "${globals.username}";
    mode = "744";
  };

  launchd.agents = {
    rclone-keepass = {
      enable = true;
      config = {
        Program = "rclone";
        ProgramArguments = [
          "bisync"
          "drive:KeePass"
          "/Users/${globals.username}/KeePass"
          "--drive-skip-gdocs"
          "--resilient"
          "--create-empty-src-dirs"
          "--fix-case"
          "--compare size,modtime,checksum"
          "--slow-hash-sync-only"
        ];
        RunAtLoad = true;
        StartInterval = 300;
      }
    };
  };
}