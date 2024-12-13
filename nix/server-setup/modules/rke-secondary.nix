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
    services.rke2 = {
      enable = true;
      nodeName = "mac-cluster-server-2";

      tokenFile = "/var/lib/rancher/rke2/server/token";
      serverAddr = "https://192.168.86.192:9345";

      cni = "calico";
    };
  }
}