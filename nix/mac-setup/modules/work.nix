{ inputs, pkgs, globals, ... }:

{
  imports = [
    ./guided-setup.nix
    ./work-docker.nix
  ];

  environment.systemPackages = [
    pkgs.awscli2
    pkgs.helm-docs
  ];

  homebrew = {
    casks = [
      "slack"
      "insomnia"
      "keeper-password-manager"
      "microsoft-remote-desktop"
      "openvpn-connect"
      "microsoft-teams"
      "microsoft-outlook"
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
        #Slack
        "/Applications/Slack.app"
        #Keeper
        "/Applications/Keeper Password Manager.app"
      ];
    };
  };
}