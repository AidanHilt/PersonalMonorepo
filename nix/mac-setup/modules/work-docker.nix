{ inputs, pkgs, globals, ... }:

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
  environment.systemPackages = [
    pkgs.colima
    pkgs.docker
    pkgs.docker-buildx
    gen3-helm-install
    gen3-edit-values
  ];

  # Launch Colima on startup, so we always have docker working
  launchd.user.agents.colima-autostart = {
    path = [ "/bin" "/usr/bin" "/nix/var/nix/profiles/default/bin" ];

    serviceConfig = {
      Label = "com.user.colima-autostart";
      ProgramArguments = [ "colima" "start" ];
      RunAtLoad = true;
      KeepAlive = false;
      StandardOutPath = "/tmp/colima-autostart.log";
      StandardErrorPath = "/tmp/colima-autostart.error.log";
    };
  };

  homebrew = {
    enable = true;

    brews = [
      "docker-credential-helper"
    ];
  };
}