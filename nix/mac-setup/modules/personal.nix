{ inputs, config, pkgs, ... }:

let
  p2n = (inputs.poetry2nix.lib.mkPoetry2Nix { inherit pkgs; });
  atils = p2n.mkPoetryApplication {
    projectDir = builtins.fetchGit {
      url = "https://github.com/AidanHilt/PersonalMonorepo.git";
      ref = "feat/nix-darwin";
      rev = "68599952e3b9ddb57fd6bca00279cd77426022c0"; #pragma: allowlist secret
    } + "/atils";

    groups = ["main"];

#    overrides = p2n.overrides.withDefaults (final: prev: { ruff = pkgs.ruff; });
  };
in

{
  age.secrets.smb-mount-config = {
    file = ../secrets/smb-mount-config.age;
    path = "/etc/smb_mount";
    symlink = false;
  };

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
    atils
  ];

  environment.etc = {
    auto_master = {
      text = ''
#
# Automounter master map
#
+auto_master    # Use directory service
#/net     -hosts    -nobrowse,hidefromfinder,nosuid
/home     auto_home -nobrowse,hidefromfinder
/Network/Servers  -fstab
/-      -static
/-      smb_mount
      '';
    };
  };
}