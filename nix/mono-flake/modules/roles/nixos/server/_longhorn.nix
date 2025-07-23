{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  environment.systemPackages = with pkgs; [
    openiscsi
  ];

  services.openiscsi = {
    enable = true;
    name = machine-config.hostname;
  };
}