{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [];

  # TODO Parsec works, but it's kind of ugly. See if we can add a pretty application too
  environment.systemPackages = lib.mkIf (pkgs.system == "x86_64-linux") (with pkgs; [
    discord
    sunshine
    lutris
    gogdl
    heroic
    usbutils
    linuxKernel.packages.linux_zen.xone
    pavucontrol
    # itch
  ]);

  hardware.xone.enable = true;
  hardware.bluetooth.enable = true;

  boot.kernelModules = [ "xone" ];

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # Make sure your user is in the audio group
  users.users.${machine-config.username}.extraGroups = [ "audio" ];

  programs.steam = lib.mkIf (pkgs.system == "x86_64-linux") {
    enable = true;
  };

  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
  };
}