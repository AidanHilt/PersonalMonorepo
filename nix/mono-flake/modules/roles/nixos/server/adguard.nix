{ inputs, globals, pkgs, machine-config, ...}:

{
  environment.systemPackages = [
    pkgs.adguardhome
  ];

  services.adguardhome = {
    enable = true;
    mutableSettings = false;
    port = 3000;
  };

  networking.firewall = {
    allowedTCPPorts = [ 53 3000 ];
    allowedUDPPorts = [ 53 ];
  };

  age.secrets.adguardhome = {
    file = ../../../../secrets/adguardhome.age;
    path = "/var/lib/private/AdGuardHome/AdGuardHome.yaml";
    symlink = false;
  };
}