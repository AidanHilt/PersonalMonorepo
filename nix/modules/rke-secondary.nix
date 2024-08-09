{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.services.rke-secondary;
in
{
  options.services.rke-secondary = {
    enable = mkEnableOption "Enable RKE2 as an agent";

    serverAddr = mkOption {
      type = types.str;
    };
    tokenFile = mkOption {
      type = types.str;
    };
  };

  config = mkIf cfg.enable {
    systemd.services.rke2 = {
      enable = true;
      role = "agent";

      serverAddr = cfg.serverAddr;
      tokenFile = cfg.tokenFile;
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
  };
}