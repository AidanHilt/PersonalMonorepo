{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  environment.systemPackages = with pkgs;[
    adguardhome
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
    path = "/var/lib/AdGuardHome/AdGuardHome.yaml";
    symlink = false;
    owner = "nogroup";
    group = "nogroup";
    mode = "700";
  };
}