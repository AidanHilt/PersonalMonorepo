{
  defaultValues = "prod-cluster";

  hashedPassword = "$y$j9T$lGgxdlwzcffl.og1ujlFT/$oY47211OBr5i0rLMFH6zNxy1QJg9p5U2WkSllcDRK90";

  k8s = {
    primaryNode = false;
  };

  networking = {
    address = "192.168.86.5";
    mainNetworkInterface = "enp0s31f6";
  };
}
