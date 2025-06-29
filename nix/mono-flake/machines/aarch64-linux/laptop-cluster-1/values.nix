{
  username = "";

  defaultValuesFile = ../../../modules/shared-values/laptop-cluster.nix;

  k8s = {
    primaryNode = true;
  };

  networking = {
    address = "192.168.86.20";
  };
}
