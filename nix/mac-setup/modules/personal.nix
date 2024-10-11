{ inputs, config, pkgs, ... }:

let
  agenix = {
    imports = [ inputs.agenix.nixosModules.age ];
    environment.systemPackages = [ inputs.agenix.packages.${pkgs.system}.agenix ];
  };
in

{
  age.secrets.smb-mount-config = {
    file = ../secrets/smb-mount-config.age;
    path = "/etc/smb_mount";
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

  imports = [ agenix ];

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