{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  environment.systemPackages = with pkgs; [
    colima
    docker
    docker-buildx
  ];

  launchd.agents."colima.autostartt" = {
    command = "${pkgs.colima}/bin/colima start --foreground --cpu 4 --memory 8 --network-address";
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
      "chipmk/tap/docker-mac-net-connect"
    ];
  };

launchd.daemons.docker-mac-net-connect = {
  serviceConfig = {
    Label = "com.docker-mac-net-connect";
    ProgramArguments = [
      "/bin/bash"
      "-c"
      ''
        while ! /opt/homebrew/bin/colima status &>/dev/null; do
          sleep 5
        done
        exec /opt/homebrew/bin/docker-mac-net-connect
      ''
    ];
    RunAtLoad = true;
    StandardOutPath = "/tmp/docker-mac-net-connect.log";
    StandardErrorPath = "/tmp/docker-mac-net-connect.err";
  };
};
}