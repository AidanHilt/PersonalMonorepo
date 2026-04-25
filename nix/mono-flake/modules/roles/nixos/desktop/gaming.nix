{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [];

  # TODO Parsec works, but it's kind of ugly. See if we can add a pretty application too
  environment.systemPackages = lib.mkIf (pkgs.system == "x86_64-linux") (with pkgs; [
    discord
    sunshine
    # TODO This was causing build failures, due to issues with tests in openLDAP. Not sure if we even need this, but that might need to be resolved
    #lutris
    gogdl
    heroic
    usbutils
    linuxKernel.packages.linux_zen.xone
    pavucontrol
    # itch
  ]);

  hardware.xone.enable = true;
  hardware.bluetooth.enable = true;

  powerManagement.cpuFreqGovernor = "schedutil";

  boot.kernelModules = [ "xone" ];

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  programs.gamemode.enable = true;

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