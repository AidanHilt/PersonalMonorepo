{
  dnsHosts = {
    # =================
    # Personal Machines
    # =================
    "192.168.86.40" = ["big-boi-desktop.fart"];

    # ===================
    # 3-node prod cluster
    # ===================
    "192.168.86.4" = ["optiplex-node.fart"];
    "192.168.86.5" = ["gaming-pc-node.fart"];
    "192.168.86.6" = ["laptop-node.fart"];

    # =====================
    # 2-node laptop cluster
    # =====================
    "192.168.86.20" = ["laptop-cluster-1.fart"];
    "192.168.86.21" = ["laptop-cluster-2.fart"];

    # =========================
    # 3-node VM staging cluster
    # =========================
    "192.168.86.24" = ["staging-cluster-1.fart"];
    "192.168.86.25" = ["staging-cluster-2.fart"];
    "192.168.86.26" = ["staging-cluster-3.fart"];
  };

  wildcardEntries = [
    "address=/*.prod-cluster-node-lb.fart/192.168.86.3"
    # This is different from the usual convention, because 192.168.86.2 (optiplex-node) is what was used in the old setup
    "address=/*.prod-cluster-lb.fart/192.168.86.13"

    "address=/*.staging-cluster-node-lb.fart/192.168.86.22"
    "address=/*.staging-cluster-lb.fart/192.168.86.23"

    "address=/*.laptop-cluster-node-lb.fart/192.168.86.18"
    "address=/*.laptop-cluster-lb.fart/192.168.86.19"
  ];
}