{
  dnsHosts = {
    # =================
    # Personal Machines
    # =================
    "192.168.86.5" = ["big-boi-desktop.local"];

    # ===================
    # 3-node prod cluster
    # ===================
    "192.168.86.2" = ["optiplex-node.local" "crafty.optiplex.local"];
    "192.168.86.3" = ["gaming-pc-node.local" "crafty.gaming-pc-node.local"];

    # =====================
    # 2-node laptop cluster
    # =====================
    "192.168.86.20" = ["laptop-cluster-1.local"];
    "192.168.86.21" = ["laptop-cluster-2.local"];

    # =========================
    # 3-node VM staging cluster
    # =========================
    "192.168.86.24" = ["staging-cluster-1.local"];
    "192.168.86.25" = ["staging-cluster-2.local"];
    "192.168.86.26" = ["staging-cluster-3.local"];


  };

  wildcardEntries = [
    "address=/*.staging-cluster-node-lb.local/192.168.86.22"
    "address=/*.staging-cluster-lb.local/192.168.86.23"

    "address=/*.laptop-cluster-node-lb.local/192.168.86.18"
    "address=/*.laptop-cluster-lb.local/192.168.86.19"
  ];
}