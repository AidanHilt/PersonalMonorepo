{ pkgs, ... }:

let
  machine-config = {
    username = "aidan";

    hostname = "macbook-cluster-2";

    networking = {
      address = "192.168.86.21";
    };

    k8s = {
      primaryNode = false;
    };
  };

  category-config = import ../../../modules/shared-values/laptop-vm-cluster.nix;

  final-output = pkgs.lib.recursiveUpdate machine-config category-config;
in
  final-output