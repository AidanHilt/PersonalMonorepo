{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ./_smb-mount.nix

    ./rclone.nix

    ../../scripts/nixos/default.nix
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
      "dupeguru"
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