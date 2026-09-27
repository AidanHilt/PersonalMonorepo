{ inputs, globals, pkgs, machine-config, lib, ...}:

let
  adGuardEnabled = if machine-config ? adguardhome.enabled then machine-config.adguardhome.enabled else true;
in

{
  environment.systemPackages = with pkgs; lib.mkIf adGuardEnabled [
    adguardhome
  ];

  services.adguardhome = lib.mkIf adGuardEnabled {
    enable = true;
    mutableSettings = false;
    port = 3000;
  };

  networking.firewall = lib.mkIf adGuardEnabled {
    allowedTCPPorts = [ 53 3000 ];
    allowedUDPPorts = [ 53 ];
  };

  age.secrets.adguardhome = lib.mkIf adGuardEnabled {
    file = ../../../../secrets/adguardhome.age;
    path = "/var/lib/AdGuardHome/AdGuardHome.yaml";
    symlink = false;
    mode = "744";
  };
}