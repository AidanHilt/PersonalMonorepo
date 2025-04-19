{
  networking = {
    address = "192.168.86.20";
  };

  k8s = {
    primaryNode = true;
  };
} // import ../shared-values/laptop-vm-cluster.nix