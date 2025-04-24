{ ... }:

let
  machine-config = {
    networking = {
      address = "192.168.86.20";
    };

    k8s = {
      primaryNode = true;
    };
  };

  category-config = import ../../shared-values/laptop-vm-cluster.nix;

  final-output = pkgs.lib.recursiveUpdate machine-config category-config;
in
  final-output