{
  imports = [
   ../shared-values/laptop-vm-cluster.nix
  ];

  networking = {
    address = "192.168.86.20";
  };

  k8s = {
    primaryNode = true;
  }
}