{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.services.rke-secondary;
in
{
  options.services.rke-secondary = {
    serverAddr = mkOption {
      type = types.str;
    };
    tokenFile = mkOption {
      type = types.str;
    };
  };


  services.rke2 = {
    enable = true;
    cni = "calico";

    serverAddr = cfg.serverAddr;
    tokenFile = cfg.tokenFile;
  };

  config.networking.firewall = {
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