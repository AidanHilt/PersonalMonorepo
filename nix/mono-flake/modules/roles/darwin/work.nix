{ inputs, globals, pkgs, machine-config, lib, ...}:

let
  gen3-helm-install = pkgs.writeShellScriptBin "gen3-helm-install" ''
  cd ~/Gen3Repos/gen3-helm/helm/gen3 && helm dependency update && helm dependency build
  helm upgrade --install gen3 ~/Gen3Repos/gen3-helm/helm/gen3 -f ~/.gen3/local-values.yaml
  '';

  gen3-edit-values = pkgs.writeShellScriptBin "gen3-edit-values" ''
  vi ~/.gen3/local-values.yaml
  '';
in

{
  environment.systemPackages = with pkgs; [
    awscli2
    helm-docs

    gen3-helm-install
    gen3-edit-values
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
