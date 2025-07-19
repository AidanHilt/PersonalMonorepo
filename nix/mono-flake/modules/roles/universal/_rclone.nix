{ inputs, globals, pkgs, machine-config, lib, ...}:

let 
  constants = import _rclone-constants.nix;
in

{
  environment.systemPackages = with constants; [
    syncDownloadAll
    syncKeepass
    syncWallpapers

    pkgs.rclone
  ] ++ wslScripts;

  environment.sessionVariables = with constants; {
    WALLPAPER_DIR = wallpaperDir;
    KEEPASS_DIR = keePassDir;
    WINDOWS_DOCUMENTS_DIR = windowsDocumentsDir;
    WINDOWS_GHUB_CONFIG_DIR = windowsGHubConfigDir;
  };

    # TODO update this so we encrypt files in Google Drive, for extra oomph
  age.secrets.rclone-config = {
    file = ../../../secrets/rclone-config.age;
    path = "/${machine-config.userBase}/${machine-config.username}/.config/rclone/rclone.conf";
    owner = "${machine-config.username}";
    group = pkgs.lib.mkIf (! pkgs.lib.hasSuffix "darwin" pkgs.system) "${machine-config.username}";
    mode = "400";
    symlink = false;
  };
}