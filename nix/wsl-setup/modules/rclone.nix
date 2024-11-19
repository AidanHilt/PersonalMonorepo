{ inputs, pkgs, globals, ... }:

let
  sync-wallpapers = pkgs.writeShellScriptBin "sync-wallpapers" ''
  rclone bisync drive:Wallpapers $WINDOWS_HOME_DIR/Wallpapers --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  sync-keepass = pkgs.writeShellScriptBin "sync-keepass" ''
  rclone bisync drive:KeePass $WINDOWS_HOME_DIR/KeePass --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  sync-documents = pkgs.writeShellScriptBin "sync-documents" ''
  rclone sync $WINDOWS_DOCUMENTS_DIR drive:Documents --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  windows-home-dir = "/mnt/c/Users/Aidan";
  windows-documents-dir = "/mnt/d/Documents";
in

{

  environment.sessionVariables = {
    WINDOWS_HOME_DIR = windows-home-dir;
    WINDOWS_DOCUMENTS_DIR = windows-documents-dir;
  };

  environment.systemPackages = [
    pkgs.rclone
    sync-wallpapers
    sync-keepass
    sync-documents
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

      keepass-sync = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = "5m";
          Unit = "keepass-sync.service";
        };
      };

      documents-folder-sync = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = "5m";
          Unit = "documents-folder-sync.service";
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

      keepass-sync = {
        script = ''
          set -xe
          ${pkgs.rclone}/bin/rclone bisync drive:KeePass ${windows-home-dir}/KeePass --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync --config /home/nixos/.config/rclone/rclone.conf
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
      };

      documents-folder-sync = {
        script = ''
          set -xe
          ${pkgs.rclone}/bin/rclone bisync drive:KeePass ${windows-home-dir}/KeePass --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync --config /home/nixos/.config/rclone/rclone.conf
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
      };
    };
  };

}