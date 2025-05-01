{ inputs, globals, pkgs, machine-config, ...}:

let
  sync-wallpapers = pkgs.writeShellScriptBin "sync-wallpapers" ''
  rclone bisync drive:Wallpapers ~/Wallpapers --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  sync-keepass = pkgs.writeShellScriptBin "sync-keepass" ''
  rclone bisync drive:KeePass ~/KeePass --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';
in

{

  environment.systemPackages = [
    pkgs.rclone

    sync-wallpapers
    sync-keepass
  ];

  # TODO update this so we encrypt files in Google Drive, for extra oomph
  age.secrets.rclone-config = {
    file = ../../../secrets/rclone-config.age;
    path = "/Users/${machine-config.username}/.config/rclone/rclone.conf";
    owner = "${machine-config.username}";
    mode = "744";
  };

  launchd.agents = {
    rcloneKeepass = {
      serviceConfig = {
        UserName = "${machine-config.username}";
        Program = /run/current-system/sw/bin/rclone;
        ProgramArguments = [
          "/run/current-system/sw/bin/rclone"
          "bisync"
          "drive:KeePass"
          "/Users/${machine-config.username}/KeePass"
          "--drive-skip-gdocs"
          "--resilient"
          "--create-empty-src-dirs"
          "--fix-case"
          "--slow-hash-sync-only"
          "--config=/Users/${machine-config.username}/.config/rclone/rclone.conf"
        ];
        RunAtLoad = true;
        StartInterval = 300;
        StandardErrorPath = /tmp/rclone-keepass.log.err;
        StandardOutPath = /tmp/rclone-keepass.log.out;
      };
    };


    rcloneWallpapers = {
      serviceConfig = {
        UserName = "${machine-config.username}";
        Program = /run/current-system/sw/bin/rclone;
        ProgramArguments = [
          "/run/current-system/sw/bin/rclone"
          "bisync"
          "drive:Wallpapers"
          "/Users/${machine-config.username}/Wallpapers"
          "--drive-skip-gdocs"
          "--resilient"
          "--create-empty-src-dirs"
          "--fix-case"
          "--slow-hash-sync-only"
          "--config=/Users/${machine-config.username}/.config/rclone/rclone.conf"
        ];
        RunAtLoad = true;
        StartInterval = 300;
        StandardErrorPath = /tmp/rclone-wallpapers.log.err;
        StandardOutPath = /tmp/rclone-wallpapers.log.out;
      };
    };
  };
}