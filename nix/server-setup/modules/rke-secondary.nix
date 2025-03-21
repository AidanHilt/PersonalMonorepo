{ lib, config, pkgs, clusterPrimaryAddr, ... }:
with lib;

{
  services.rke2 = {
    enable = true;

    tokenFile = "/var/lib/rancher/rke2/server/token";
    serverAddr = "https://${clusterPrimaryAddr}:9345";

    cni = "calico";
  };
}