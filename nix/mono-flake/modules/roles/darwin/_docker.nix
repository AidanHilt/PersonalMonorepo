{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  environment.systemPackages = with pkgs; [
    colima
    docker
    docker-buildx
  ];

  launchd.agents."colima.autostartt" = {
    command = "${pkgs.colima}/bin/colima start --foreground --cpu 4 --memory 8";
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