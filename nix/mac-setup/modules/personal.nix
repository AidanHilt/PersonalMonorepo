{ inputs, pkgs, globals, ... }:

let
  kubernetes-config = globals.nixConfig + "/shared-modules/kubernetes.nix";
in

{
  imports = [
    ./smb-mount.nix
    ./rclone.nix
    ./guided-setup.nix
    ./hosts.nix
    kubernetes-config
  ];

  environment.systemPackages = [
    pkgs.python312
    pkgs.poetry
  ];

  homebrew = {
    casks = [
      "discord"
      "steam"
      "vlc"
      "parsec"
      "keepassxc"
      "spotify"
      "tor-browser"
      "orbstack"
      "postman"
      "utm"
      "prismlauncher"
      "crystalfetch"
    ];
  };

  system.defaults = {
    dock = {
      persistent-apps = [
        #iTerm
        "/Applications/iTerm.app"
        #Settings
        "/System/Applications/System Settings.app"
        #Firefox
        "/Applications/Firefox.app"
        #VSCode
        "/Applications/Visual Studio Code.app"
        #Discord
        "/Applications/Discord.app"
        #Parsec
        "/Applications/Parsec.app"
        #Spotify
        "/Applications/Spotify.app"
        #Orbstack
        "/Applications/OrbStack.app"
        #ActivityMonitor
        "/System/Applications/Utilities/Activity Monitor.app"
        #KeePassXC
        "/Applications/KeePassXC.app"
      ];
    };
  };
}