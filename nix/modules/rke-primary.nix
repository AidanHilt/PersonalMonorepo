{ config, pkgs, inputs, ... }:

{
  services.rke2 = {
    enable = true;
    role = "server";

    cni = "calico";
  };

  networking.firewall = {
    # See https://docs.rke2.io/install/requirements#inbound-network-rules for details
    allowedTCPPorts = [ 9345 6443 ];
    allowedTCPPortRanges = [
      {
        from = 30000;
        to = 32767;
      }
    ];
  };
}