{ inputs, globals, pkgs, ...}:

{
  environment.systemPackages = [
    pkgs.adguardhome
  ];

  services.adguardhome = {
    enable = true;
    mutableSettings = false;
  };

  networking.firewall = {
    allowedTCPPorts = [ 53 3000 ];
    allowedUDPPorts = [ 53 ];
  };
}