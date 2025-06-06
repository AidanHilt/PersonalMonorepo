{ inputs, globals, pkgs, machine-config, ...}:

let
  sync-wallpapers = pkgs.writeShellScriptBin "sync-wallpapers" ''
  rclone bisync drive:Wallpapers $WINDOWS_HOME_DIR/Wallpapers --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  sync-keepass = pkgs.writeShellScriptBin "sync-keepass" ''
  rclone bisync drive:KeePass $WINDOWS_HOME_DIR/KeePass --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  sync-documents = pkgs.writeShellScriptBin "sync-documents" ''
  rclone sync $WINDOWS_DOCUMENTS_DIR drive:Documents --drive-skip-gdocs --create-empty-src-dirs --fix-case
  '';

  sync-lg-ghub = pkgs.writeShellScriptBin "sync-lg-ghub" ''
  rclone sync $WINDOWS_HOME_DIR/AppData/local/LGHUB drive:GHUB-Windows--drive-skip-gdocs --create-empty-src-dirs --fix-case
  '';

  sync-download-all = pkgs.writeShellScriptBin "sync-download-all" ''
  mkdir $WINDOWS_HOME_DIR/Wallpapers
  mkdir $WINDOWS_HOME_DIR/KeePass
  mkdir $WINDOWS_HOME_DIR/AppData/local/LGHUB

  rclone bisync drive:Wallpapers $WINDOWS_HOME_DIR/Wallpapers --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  rclone bisync drive:KeePass $WINDOWS_HOME_DIR/KeePass --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  rclone sync drive:Documents $WINDOWS_DOCUMENTS_DIR --drive-skip-gdocs --create-empty-src-dirs --fix-case
  rclone sync drive:GHUB-Windows $WINDOWS_HOME_DIR/AppData/local/LGHUB --drive-skip-gdocs --create-empty-src-dirs --fix-case
  '';

  windows-home-dir = "/mnt/d/Users/aidan";
  windows-documents-dir = "/mnt/d/Users/aidan/Documents";
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
    sync-lg-ghub
  ];

  # TODO update this so we encrypt files in Google Drive, for extra oomph
  age.secrets.rclone-config = {
    file = ../../../secrets/rclone-config.age;
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
          OnBootSec = "30m";
          OnUnitActiveSec = "30m";
          Unit = "documents-folder-sync.service";
        };
      };

      lg-ghub-sync = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "30m";
          OnUnitActiveSec = "30m";
          Unit = "lg-ghub-sync.service";
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
          ${pkgs.rclone}/bin/rclone sync ${windows-documents-dir} drive:Documents --drive-skip-gdocs --create-empty-src-dirs --fix-case --config /home/nixos/.config/rclone/rclone.conf
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
      };

      lg-ghub-sync = {
        script = ''
          set -xe
          ${pkgs.rclone}/bin/rclone sync ${windows-home-dir}/AppData/local/LGHUB drive:GHUB-Windows--drive-skip-gdocs --create-empty-src-dirs --fix-case --config /home/nixos/.config/rclone/rclone.conf
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
      };
    };
  };

}