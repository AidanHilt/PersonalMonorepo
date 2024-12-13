{ lib, config, pkgs, serverAddr, ... }:
with lib;

{
  services.rke2 = {
    enable = true;

    tokenFile = "/var/lib/rancher/rke2/server/token";
    serverAddr = "https://${serverAddr}:9345";

    cni = "calico";
  };
}