{
  dnsHosts = {
    # =================
    # Personal Machines
    # =================
    "192.168.86.40" = ["big-boi-desktop.lan"];

    # ===================
    # 3-node prod cluster
    # ===================
    "192.168.86.2" = ["*.prod-cluster-node-lb.lan"];
    "192.168.86.3" = ["*.prod-cluster-lb.lan"];

    "192.168.86.4" = ["optiplex-node.lan"];
    "192.168.86.5" = ["gaming-pc-node.lan"];
    "192.168.86.6" = ["laptop-node.lan"];

    # =====================
    # 2-node laptop cluster
    # =====================
    "192.168.86.20" = ["laptop-cluster-1.lan"];
    "192.168.86.21" = ["laptop-cluster-2.lan"];

    # =========================
    # 3-node VM staging cluster
    # =========================
    "192.168.86.24" = ["staging-cluster-1.lan"];
    "192.168.86.25" = ["staging-cluster-2.lan"];
    "192.168.86.26" = ["staging-cluster-3.lan"];

    # =========================
    # Load Balancers (wildcard)
    # =========================
    "192.168.86.22" = ["*.staging-cluster-node-lb.lan"];
    "192.168.86.23" = ["*.staging-cluster-lb.lan"];
    "192.168.86.18" = ["*.laptop-cluster-node-lb.lan"];
    "192.168.86.19" = ["*.laptop-cluster-lb.lan"];
    "172.18.255.200" = ["*.qa-cluster-lb.lan"];
  };
}