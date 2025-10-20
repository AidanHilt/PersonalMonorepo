{ inputs, globals, pkgs, machine-config, lib, ...}:

let
  interface = machine-config.networking.mainNetworkInterface or "enp0s1";
in

{
  environment.systemPackages = [
    pkgs.keepalived
  ];

  services.keepalived = {
    enable = true;
    openFirewall = true;

    vrrpInstances.adguardhome = {
      interface = interface;
      priority = 100;
      virtualRouterId = machine-config.networking.virtualRouterId;
      virtualIps = [{ addr = machine-config.networking.loadBalancerIp; }];
    };
  };
}