{
  defaultValues = "prod-cluster";

  k8s = {
    primaryNode = true;
  };

  networking = {
    address = "192.168.86.6";
  };
}
