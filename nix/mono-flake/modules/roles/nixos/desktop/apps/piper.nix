{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [];

  environment.systemPackages = with pkgs; [
    piper
  ];

  services.ratbagd.enable = true;
}