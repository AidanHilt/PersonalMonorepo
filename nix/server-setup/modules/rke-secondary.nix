{ lib, config, pkgs, serverAddr, ... }:
with lib;

{
  services.rke2 = {
    enable = true;

    tokenFile = "/var/lib/rancher/rke2/server/token";
    serverAddr = "https://${serverAddr}:9345";

    cni = "calico";
  };

  networking.firewall = {
    # See https://docs.rke2.io/install/requirements#inbound-network-rules for details
    allowedTCPPorts = [ 6443 6444 9345 10250 2379 2380 2381 9099 5473 ];
    allowedTCPPortRanges = [
      {
        from = 30000;
        to = 32767;
      }
    ];
  };
}