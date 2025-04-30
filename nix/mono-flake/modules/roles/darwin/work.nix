{ inputs, globals, pkgs, machine-config, ...}:

let
 awsSignIn = pkgs.writeShellScriptBin "aws-signin" ''
  aws sso login --profile my-sso
  export AWS_PROFILE=csoc
 '';
in

{
  imports = [
    ./guided-setup.nix
    ./work-docker.nix
  ];

  environment.systemPackages = [
    pkgs.awscli2
    pkgs.helm-docs
    awsSignIn
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
