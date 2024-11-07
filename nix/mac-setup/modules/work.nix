{ inputs, pkgs, globals, ... }:

{
  imports = [
    ./guided-setup.nix
  ];

  environment.systemPackages = [
    pkgs.colima
    pkgs.awscli2
    pkgs.helm-docs
  ];

  homebrew = {
    casks = [
      "slack"
      "insomnia"
      "keeper-password-manager"
      "microsoft-remote-desktop"
      "tunnelblick"
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