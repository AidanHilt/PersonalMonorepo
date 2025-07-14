{ inputs, globals, pkgs, machine-config, ...}:

let 

  wallpaperDir = if machine-config ? rcloneSync.wallpaperDir then machine-config.rcloneSync.wallpaperDir else "${machine-config.userBase}/${machine-config.username}/Wallpapers";
  keePassDir = if machine-config ? rcloneSync.keePassDir then machine-config.rcloneSync.keePassDir else "${machine-config.userBase}/${machine-config.username}/KeePass";
  
  
  windowsDocumentsDir = if machine-config ? rcloneSync.windowsDocumentsDir then machine-config.rcloneSync.windowsDocumentsDir else "/mnt/d/Users/aidan/Documents";
  windowsHomeDir = if machine-config ? rcloneSync.windowsHomeDirDir then machine-config.rcloneSync.windowsHomeDir else "/mnt/d/Users/aidan";
  windowsGHubConfigDir = if machine-config ? rcloneSync.windowsGHubConfigDir then machine-config.rcloneSync.windowsGHubConfigDir else "${windowsHomeDir}/AppData/local/LGHUB";

  syncWallpapers = pkgs.writeShellScriptBin "sync-wallpapers" ''
    rclone bisync drive:Wallpapers $WALLPAPER_DIR --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  syncKeepass = pkgs.writeShellScriptBin "sync-keepass" ''
    rclone bisync drive:KeePass $KEEPASS_DIR --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  syncDocuments = pkgs.writeShellScriptBin "sync-documents" ''
    rclone sync $WINDOWS_DOCUMENTS_DIR drive:Documents --drive-skip-gdocs --create-empty-src-dirs --fix-case
  '';

  syncGHub = pkgs.writeShellScriptBin "sync-g-hub" ''
    rclone sync $WINDOWS_GHUB_CONFIG_DIR drive:GHUB-Windows--drive-skip-gdocs --create-empty-src-dirs --fix-case
  '';

  wsl = if machine-config ? configSwitches.wsl then machine-config.configSwitches.wsl else false;

  wslScripts = if wsl then [syncDocuments syncGHub] else [];

  syncDownloadAll = if wsl then 
    pkgs.writeShellScriptBin "sync-download-all" ''
      mkdir $WALLPAPER_DIR
      mkdir $KEEPASS_DIR
      mkdir $WINDOWS_GHUB_CONFIG_DIR

      sync-wallpapers
      sync-keepass
      sync-documents
      sync-g-hub
  '' 
  else 
    pkgs.writeShellScriptBin "sync-download-all" ''
      mkdir $WALLPAPER_DIR
      mkdir $KEEPASS_DIR

      sync-wallpapers
      sync-keepass
    ''
  ;

in

{
  imports = [];

  environment.systemPackages = with pkgs; [
    syncDownloadAll
    syncKeepass
    syncWallpapers

    rclone
  ] ++ wslScripts;

  environment.sessionVariables = {
    WALLPAPER_DIR = "${wallpaperDir}";
    KEEPASS_DIR = "${keePassDir}";
    WINDOWS_DOCUMENTS_DIR = "${windowsDocumentsDir}";
    WINDOWS_GHUB_CONFIG_DIR = "${windowsGHubConfigDir}";
  };

    # TODO update this so we encrypt files in Google Drive, for extra oomph
  age.secrets.rclone-config = {
    file = ../../../secrets/rclone-config.age;
    path = "/${machine-config.userBase}/${machine-config.username}/.config/rclone/rclone.conf";
    owner = "${machine-config.username}";
    group = pkgs.lib.mkIf (pkgs.lib.hasSuffix "darwin" pkgs.system) "${machine-config.username}";
    mode = "400";
    symlink = false;
  };

  # launchd.agents = pkgs.lib.mkIf (pkgs.lib.hasSuffix "darwin") {
  #   rcloneKeepass = {
  #     serviceConfig = {
  #       UserName = "${machine-config.username}";
  #       Program = /run/current-system/sw/bin/rclone;
  #       ProgramArguments = [
  #         "/run/current-system/sw/bin/rclone"
  #         "bisync"
  #         "drive:KeePass"
  #         "/Users/${machine-config.username}/KeePass"
  #         "--drive-skip-gdocs"
  #         "--resilient"
  #         "--create-empty-src-dirs"
  #         "--fix-case"
  #         "--slow-hash-sync-only"
  #         "--config=/Users/${machine-config.username}/.config/rclone/rclone.conf"
  #       ];
  #       RunAtLoad = true;
  #       StartInterval = 300;
  #       StandardErrorPath = /tmp/rclone-keepass.log.err;
  #       StandardOutPath = /tmp/rclone-keepass.log.out;
  #     };
  #   };


  #   rcloneWallpapers = {
  #     serviceConfig = {
  #       UserName = "${machine-config.username}";
  #       Program = /run/current-system/sw/bin/rclone;
  #       ProgramArguments = [
  #         "/run/current-system/sw/bin/rclone"
  #         "bisync"
  #         "drive:Wallpapers"
  #         "/Users/${machine-config.username}/Wallpapers"
  #         "--drive-skip-gdocs"
  #         "--resilient"
  #         "--create-empty-src-dirs"
  #         "--fix-case"
  #         "--slow-hash-sync-only"
  #         "--config=/Users/${machine-config.username}/.config/rclone/rclone.conf"
  #       ];
  #       RunAtLoad = true;
  #       StartInterval = 300;
  #       StandardErrorPath = /tmp/rclone-wallpapers.log.err;
  #       StandardOutPath = /tmp/rclone-wallpapers.log.out;
  #     };
  #   };
  # };

  # systemd = pkgs.lib.mkIf (! pkgs.lib.hasSuffix "darwin") {
  #   timers = {
  #     wallpaper-sync = {
  #       wantedBy = [ "timers.target" ];
  #       timerConfig = {
  #         OnBootSec = "5m";
  #         OnUnitActiveSec = "5m";
  #         Unit = "wallpaper-sync.service";
  #       };
  #     };

  #     keepass-sync = {
  #       wantedBy = [ "timers.target" ];
  #       timerConfig = {
  #         OnBootSec = "5m";
  #         OnUnitActiveSec = "5m";
  #         Unit = "keepass-sync.service";
  #       };
  #     };

  #     documents-folder-sync = {
  #       wantedBy = [ "timers.target" ];
  #       timerConfig = {
  #         OnBootSec = "30m";
  #         OnUnitActiveSec = "30m";
  #         Unit = "documents-folder-sync.service";
  #       };
  #     };

  #     lg-ghub-sync = {
  #       wantedBy = [ "timers.target" ];
  #       timerConfig = {
  #         OnBootSec = "30m";
  #         OnUnitActiveSec = "30m";
  #         Unit = "lg-ghub-sync.service";
  #       };
  #     };
  #   };

  #   services = {
  #     wallpaper-sync = {
  #       script = ''
  #         set -xe
  #         ${pkgs.rclone}/bin/rclone bisync drive:Wallpapers $WALLPAPER_DIR --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync --config /home/nixos/.config/rclone/rclone.conf
  #       '';

  #       serviceConfig = {
  #         Type = "oneshot";
  #         User = "root";
  #       };
  #     };

  #     keepass-sync = {
  #       script = ''
  #         set -xe
  #         ${pkgs.rclone}/bin/rclone bisync drive:KeePass $KEEPASS_DIR --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync --config /home/nixos/.config/rclone/rclone.conf
  #       '';

  #       serviceConfig = {
  #         Type = "oneshot";
  #         User = "root";
  #       };
  #     };

  #     documents-folder-sync = {
  #       script = ''
  #         set -xe
  #         ${pkgs.rclone}/bin/rclone sync $WINDOWS_DOCUMENTS_DIR drive:Documents --drive-skip-gdocs --create-empty-src-dirs --fix-case --config /home/nixos/.config/rclone/rclone.conf
  #       '';

  #       serviceConfig = {
  #         Type = "oneshot";
  #         User = "root";
  #       };
  #     };

  #     lg-ghub-sync = {
  #       script = ''
  #         set -xe
  #         ${pkgs.rclone}/bin/rclone sync $WINDOWS_GHUB_CONFIG_DIR drive:GHUB-Windows--drive-skip-gdocs --create-empty-src-dirs --fix-case --config /home/nixos/.config/rclone/rclone.conf
  #       '';

  #       serviceConfig = {
  #         Type = "oneshot";
  #         User = "root";
  #       };
  #     };
  #   };
  # };
}