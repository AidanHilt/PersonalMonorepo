{
  dnsHosts = {
    # =================
    # Personal Machines
    # =================
    "192.168.86.40" = ["big-boi-desktop.local"];

    # ===================
    # 3-node prod cluster
    # ===================
    "192.168.86.4" = ["optiplex-node.local"];
    "192.168.86.5" = ["gaming-pc-node.local"];
    "192.168.86.6" = ["laptop-node.local"];

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
    "address=/*.prod-cluster-node-lb.local/192.168.86.3"
    # This is different from the usual convention, because 192.168.86.2 (optiplex-node) is what was used in the old setup
    "address=/*.prod-cluster-lb.local/192.168.86.23"

    "address=/*.staging-cluster-node-lb.local/192.168.86.22"
    "address=/*.staging-cluster-lb.local/192.168.86.23"

    "address=/*.laptop-cluster-node-lb.local/192.168.86.18"
    "address=/*.laptop-cluster-lb.local/192.168.86.19"
  ];
}