{ inputs, globals, pkgs, machine-config, lib, ...}:

let
  constants = import ../universal/_rclone-constants.nix {inherit pkgs machine-config lib;};
in

{
  imports = [
    ../universal/_rclone.nix
  ];

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

      atils-sync = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = "5m";
          Unit = "atils-sync.service";
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
        environment = constants.environmentVariables;
        script = ''
          set -xe
          ${pkgs.rclone}/bin/rclone bisync drive:Wallpapers $WALLPAPER_DIR --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync --config /home/${machine-config.username}/.config/rclone/rclone.conf
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
      };

      keepass-sync = {
        environment = constants.environmentVariables;
        script = ''
          set -xe
          ${pkgs.rclone}/bin/rclone bisync drive:KeePass $KEEPASS_DIR --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync --config /home/${machine-config.username}/.config/rclone/rclone.conf
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
      };

      atils-sync = {
        environment = constants.environmentVariables;
        script = ''
          set -xe
          ${pkgs.rclone}/bin/rclone bisync drive:ATILS $ATILS_CONFIG_DIRECTORY --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync --config /home/${machine-config.username}/.config/rclone/rclone.conf
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
      };

      documents-folder-sync = lib.mkIf constants.wsl {
        environment = constants.environmentVariables;
        script = ''
          set -xe
          ${pkgs.rclone}/bin/rclone sync $WINDOWS_DOCUMENTS_DIR drive:Documents --drive-skip-gdocs --create-empty-src-dirs --fix-case --config /home/${machine-config.username}/.config/rclone/rclone.conf
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
      };

      lg-ghub-sync = lib.mkIf constants.wsl {
        environment = constants.environmentVariables;
        script = ''
          set -xe
          ${pkgs.rclone}/bin/rclone sync $WINDOWS_GHUB_CONFIG_DIR drive:GHUB-Windows--drive-skip-gdocs --create-empty-src-dirs --fix-case --config /home/${machine-config.username}/.config/rclone/rclone.conf
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
      };
    };
  };
}