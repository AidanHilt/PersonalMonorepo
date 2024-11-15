{ inputs, pkgs, globals, ... }:

let
  sync-wallpapers = pkgs.writeShellScriptBin "sync-wallpapers" ''
  rclone bisync drive:Wallpapers ~/Wallpapers --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  sync-keepass = pkgs.writeShellScriptBin "sync-keepass" ''
  rclone bisync drive:KeePass ~/KeePass --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  '';

  windows-home-dir = "/mnt/c/
in

{

  environment.systemPackages = [
    pkgs.rclone
    sync-wallpapers
    sync-keepass
  ];

  # TODO update this so we encrypt files in Google Drive, for extra oomph
  age.secrets.rclone-config = {
    file = ../secrets/rclone-config.age;
    path = "/Users/${globals.username}/.config/rclone/rclone.conf";
    owner = "${globals.username}";
    mode = "744";
  };

}