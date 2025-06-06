{ pkgs, ... }:

let
  machine-config = {
    username = "";

    # TODO we probably just want to read hostname from the folder
    hostname = "";

    # imports = [
    #  ../shared-values/<machine-group>.nix
    # ];

    # networking = {
    #   fixedIp = false;

    #   defaultGateway = "";
    #   nameservers = [];
    #   address = "";
    #   prefixLength = 24;
    # }

    # k8s = {
    #   primaryNode = false;

    #   clusterEndpoint = "";
    #   # Used to identify which secrets to provide to the cluster
    #   clusterName = "";
    # };
  };

  category-config = import ../../../modules/shared-values/<category>.nix;

  final-output = pkgs.lib.recursiveUpdate machine-config category-config;
in
  final-output