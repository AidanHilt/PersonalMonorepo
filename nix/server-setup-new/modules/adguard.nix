{ inputs, globals, pkgs, ...}:

{
  environment.systemPackages = [
    pkgs.adguardhome
  ];

  services.adguardhome = {
    enable = true;
    mutableSettings = false;
  };
}