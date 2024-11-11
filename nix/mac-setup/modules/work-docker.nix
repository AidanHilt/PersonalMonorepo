{ inputs, pkgs, globals, ... }:

{
  environment.systemPackages = [
    pkgs.colima
    pkgs.docker
    pkgs.docker-buildx
  ];

  # Configuration for macOS LaunchAgent
  launchd.user.agents.colima-autostart = {
    enable = true;
    path = [ "/bin" "/usr/bin" "/nix/var/nix/profiles/default/bin" ];

    serviceConfig = {
      Label = "com.user.colima-autostart";
      ProgramArguments = [ "colima" "start" ];
      RunAtLoad = true;
      KeepAlive = false;
      StandardOutPath = "/tmp/colima-autostart.log";
      StandardErrorPath = "/tmp/colima-autostart.error.log";
    };

    # Only start if colima is installed
    requires = [ "colima" ];
  };
}