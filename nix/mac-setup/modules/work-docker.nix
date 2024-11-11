{ inputs, pkgs, globals, ... }:

let

in

{
  environment.systemPackages = [
    pkgs.colima
    pkgs.docker
    pkgs.docker-buildx
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

  environment.shellAliases = {
    "docker build" = "docker-buildx build";
  };
}