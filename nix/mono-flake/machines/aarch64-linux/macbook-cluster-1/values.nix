{ pkgs, ... }:

let
  machine-config = {
    username = "aidan";

    hostname = "macbook-cluster-1";

    networking = {
      address = "192.168.86.20";
    };

    k8s = {
      primaryNode = true;
    };
  };

  category-config = import ../../../modules/shared-values/laptop-vm-clusternix;

  final-output = pkgs.lib.recursiveUpdate machine-config category-config;
in
  final-output