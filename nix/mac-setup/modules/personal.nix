{ inputs, pkgs, globals, ... }:

{
  imports = [
    ./smb-mount.nix
    ./rclone.nix
    ./guided-setup.nix
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

  environment.systemPackages = [
    inputs.agenix.packages.${pkgs.system}.agenix
  ];
}