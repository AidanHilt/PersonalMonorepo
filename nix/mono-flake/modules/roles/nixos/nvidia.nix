{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  hardware.graphics.enable = true;

  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {
    modesetting.enable = true;

    powerManagement = {
      enable = false;
      finegrained = false;
    };

    nvidiaSettings = true;

    open = true;
  };
}