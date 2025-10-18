{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ./_smb-mount.nix

    ./hosts.nix
    ./rclone.nix
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
        #ActivityMonitor
        "/System/Applications/Utilities/Activity Monitor.app"
        #KeePassXC
        "/Applications/KeePassXC.app"
      ];
    };
  };

  nix = {
    linux-builder = {
      enable = true;
      ephemeral = false;
      systems = ["x86_64-linux" "aarch64-linux"];
      config.boot.binfmt.emulatedSystems = ["x86_64-linux"];
      config = {
        virtualisation = {
          darwin-builder = {
            diskSize = 80 * 1024;
            memorySize = 12 * 1024;
          };
          cores = 8;
        };
      };
    };

    settings = {
      trusted-users = [
        "aidan"
        "root"
      ];
    };
  };
}