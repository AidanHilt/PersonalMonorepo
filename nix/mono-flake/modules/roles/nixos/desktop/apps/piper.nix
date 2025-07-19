{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [];

  environment.systemPackages = with pkgs; [
    piper
  ];

  services.ratbagd.enable = true;
}