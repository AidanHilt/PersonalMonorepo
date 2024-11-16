{ inputs, pkgs, globals, ... }:

let
  sync-wallpapers = pkgs.writeShellScriptBin "sync-wallpapers" ''
  rclone bisync drive:Wallpapers $WINDOWS_HOME_DIR/Wallpapers --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  sync-keepass = pkgs.writeShellScriptBin "sync-keepass" ''
  rclone bisync drive:KeePass $WINDOWS_HOME_DIR/KeePass --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  windows-home-dir = "/mnt/c/Users/Aidan";
in

{

  environment.sessionVariables = {
    WINDOWS_HOME_DIR = windows-home-dir;
  };

  environment.systemPackages = [
    pkgs.rclone
    sync-wallpapers
    sync-keepass
  ];

  # TODO update this so we encrypt files in Google Drive, for extra oomph
  age.secrets.rclone-config = {
    file = globals.personalConfig + "/secrets/rclone-config.age";
    path = "/home/nixos/.config/rclone/rclone.conf";
    owner = "nixos";
    group = "nixos";
    mode = "744";
    symlink = false;
  };

  systemd = {
    timers = {
      wallpaper-sync = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = "5m";
          Unit = "wallpaper-sync.service";
        };
      };
    };

    services = {
      wallpaper-sync = {
        script = ''
          set -xe
          ${pkgs.rclone}/bin/rclone bisync drive:Wallpapers ${windows-home-dir}/Wallpapers --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync --config /home/nixos/.config/rclone/rclone.conf
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
      };
    };
  };

}