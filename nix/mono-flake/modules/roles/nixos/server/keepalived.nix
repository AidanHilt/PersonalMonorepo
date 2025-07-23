{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  environment.systemPackages = [
    pkgs.keepalived
  ];

  services.keepalived = {
    enable = true;
    openFirewall = true;

    vrrpInstances.adguardhome = {
      interface = "enp0s1";
      priority = 100;
      virtualRouterId = 81;
      virtualIps = [{ addr = machine-config.networking.loadBalancerIp; }];
    };
  };
}