{ inputs, globals, pkgs, ...}:

{
  environment.systemPackages = [
    pkgs.keepalived
  ];

  services.keepalived = {
    enable = true;

    vrrpInstances.adguardhome = {
      priority = 100;
      virtualRouterId = 81;
      virtualIps = [{ addr = "192.168.86.19"; }];
    };
  };
}