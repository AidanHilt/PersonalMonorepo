{ inputs, globals, pkgs, machine-config, ...}:

{
  launchd.agents = pkgs.lib.mkIf (pkgs.stdenv.isDarwin) {
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