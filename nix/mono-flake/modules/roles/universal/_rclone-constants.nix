{
  pkgs,
  machine-config,
  lib,
  ...
}:

let
  wallpaperDir =
    if machine-config ? rcloneSync.wallpaperDir then
      machine-config.rcloneSync.wallpaperDir
    else
      "${machine-config.userBase}/${machine-config.username}/Wallpapers";
  keePassDir =
    if machine-config ? rcloneSync.keePassDir then
      machine-config.rcloneSync.keePassDir
    else
      "${machine-config.userBase}/${machine-config.username}/KeePass";
  atilsConfigDir =
    if machine-config ? rcloneSync.atilsConfigDir then
      machine-config.rcloneSync.atilsConfigDir
    else
      "${machine-config.userBase}/${machine-config.username}/.atils";

  windowsDocumentsDir =
    if machine-config ? rcloneSync.windowsDocumentsDir then
      machine-config.rcloneSync.windowsDocumentsDir
    else
      "/mnt/d/Users/aidan/Documents";
  windowsHomeDir =
    if machine-config ? rcloneSync.windowsHomeDirDir then
      machine-config.rcloneSync.windowsHomeDir
    else
      "/mnt/d/Users/aidan";
  windowsGHubConfigDir =
    if machine-config ? rcloneSync.windowsGHubConfigDir then
      machine-config.rcloneSync.windowsGHubConfigDir
    else
      "${windowsHomeDir}/AppData/local/LGHUB";

  # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
  syncAtilsConfigDir = pkgs.writeShellScriptBin "sync-atils-config" ''
    rclone bisync drive:Atils $ATILS_CONFIG_DIRECTORY/contexts --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
  syncWallpapers = pkgs.writeShellScriptBin "sync-wallpapers" ''
    rclone bisync drive:Wallpapers $WALLPAPER_DIR --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
  syncKeepass = pkgs.writeShellScriptBin "sync-keepass" ''
    rclone bisync drive:KeePass $KEEPASS_DIR --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
  syncDocuments = pkgs.writeShellScriptBin "sync-documents" ''
    rclone sync $WINDOWS_DOCUMENTS_DIR drive:Documents --drive-skip-gdocs --create-empty-src-dirs --fix-case
  '';

  # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
  syncGHub = pkgs.writeShellScriptBin "sync-g-hub" ''
    rclone sync $WINDOWS_GHUB_CONFIG_DIR drive:GHUB-Windows--drive-skip-gdocs --create-empty-src-dirs --fix-case
  '';

  wsl = machine-config.configSwitches.wsl or false;

  wslScripts =
    if wsl then
      [
        syncDocuments
        syncGHub
      ]
    else
      [ ];

  # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
  syncDownloadAll =
    if wsl then
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
      '';
in

{
  wallpaperDir = wallpaperDir;
  keePassDir = keePassDir;

  windowsDocumentsDir = windowsDocumentsDir;
  windowsHomeDir = windowsHomeDir;
  windowsGHubConfigDir = windowsGHubConfigDir;

  syncAtilsConfigDir = syncAtilsConfigDir;

  # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
  syncWallpapers = pkgs.writeShellScriptBin "sync-wallpapers" ''
    rclone bisync drive:Wallpapers $WALLPAPER_DIR --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
  syncKeepass = pkgs.writeShellScriptBin "sync-keepass" ''
    rclone bisync drive:KeePass $KEEPASS_DIR --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
  syncDocuments = pkgs.writeShellScriptBin "sync-documents" ''
    rclone sync $WINDOWS_DOCUMENTS_DIR drive:Documents --drive-skip-gdocs --create-empty-src-dirs --fix-case
  '';

  # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
  syncGHub = pkgs.writeShellScriptBin "sync-g-hub" ''
    rclone sync $WINDOWS_GHUB_CONFIG_DIR drive:GHUB-Windows--drive-skip-gdocs --create-empty-src-dirs --fix-case
  '';

  wsl = wsl;

  wslScripts = wslScripts;

  # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
  syncDownloadAll =
    if wsl then
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
      '';

  environmentVariables = {
    WALLPAPER_DIR = wallpaperDir;
    KEEPASS_DIR = keePassDir;
    WINDOWS_DOCUMENTS_DIR = (lib.mkIf wsl) windowsDocumentsDir;
    WINDOWS_GHUB_CONFIG_DIR = (lib.mkIf wsl) windowsGHubConfigDir;
  };

}
