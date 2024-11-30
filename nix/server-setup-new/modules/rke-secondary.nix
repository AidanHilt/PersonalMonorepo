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
  };

  config = {
    systemd.services.rke2 = {
      description = "RKE2 Kubernetes Service";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.rke2}/bin/rke2 server --server ${cfg.serverAddr} --token-file /var/lib/rancher/rke2/server/token";
        Restart = "always";
        RestartSec = "5s";
      };
   };
    networking.firewall = {
     # See https://docs.rke2.io/install/requirements#inbound-network-rules for details
     allowedTCPPorts = [ 6443 9345 ];
     allowedTCPPortRanges = [
        {
          from = 30000;
          to = 32767;
        }
      ];
    };
  };
}