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
    colima
    docker
    docker-buildx

    gen3-helm-install
    gen3-edit-values
  ];

  launchd.agents."colima.autostartt" = {
    command = "${pkgs.colima}/bin/colima start --foreground";
    serviceConfig = {
      Label = "com.colima.autostart";
      RunAtLoad = true;
      KeepAlive = true;

      StandardOutPath = "/tmp/colima-autostart.log";
      StandardErrorPath = "/tmp/colima-autostart.error.log";

      EnvironmentVariables = {
        PATH = "${pkgs.colima}/bin:${pkgs.docker}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
  };

  homebrew = {
    enable = true;

    brews = [
      "docker-credential-helper"
    ];
  };
}