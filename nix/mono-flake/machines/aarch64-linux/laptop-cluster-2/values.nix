{
  defaultValues = "laptop-cluster";

  k8s = {
    primaryNode = false;
  };

  networking = {
    address = "192.168.86.21";
  };
}
