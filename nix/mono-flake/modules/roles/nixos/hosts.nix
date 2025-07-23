{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  networking.hosts = {
    # Current "prod" setup
    "192.168.86.2" = ["optiplex-node.local" "crafty.optiplex.local"];
    "192.168.86.3" = ["gaming-pc-node.local" "crafty.gaming-pc-node.local"];

    # 2-node laptop cluster
    # Load balancers
    "192.168.86.18" = ["laptop-cluster-node-lb.local"];
    "192.168.86.19" = ["laptop-cluster-lb.local"];

    # Nodes
    "192.168.86.20" = ["laptop-cluster-1.local"];
    "192.168.86.21" = ["laptop-cluster-2.local"];

    # 3-node VM staging cluster
    # Load balancers
    "192.168.86.22" = ["staging-cluster-node-lb.local"];
    "192.168.86.23" = ["staging-cluster-lb.local"];

    #Nodes
    "192.168.86.24" = ["staging-cluster-1.local"];
    "192.168.86.25" = ["staging-cluster-2.local"];
    "192.168.86.26" = ["staging-cluster-3.local"];
  };

}