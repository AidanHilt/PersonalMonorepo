{
  imports = [
   ../../../modules/shared-values/laptop-vm-cluster.nix
  ];

  networking = {
    address = "192.168.86.21";
  };

  k8s = {
    primaryNode = false;
  };
}