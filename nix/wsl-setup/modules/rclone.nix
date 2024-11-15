{ inputs, pkgs, globals, ... }:

let
  sync-wallpapers = pkgs.writeShellScriptBin "sync-wallpapers" ''
  rclone bisync drive:Wallpapers ~/Wallpapers --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  sync-keepass = pkgs.writeShellScriptBin "sync-keepass" ''
  rclone bisync drive:KeePass ~/KeePass --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  windows-home-dir = "/mnt/c/Users/Aidan";
in

{

  environment.variables = {
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
    mode = "744";
  };

}