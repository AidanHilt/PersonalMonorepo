{
  defaultValues = "prod-cluster";

  hashedPassword = "$y$j9T$fSTyEsZ09WW5mmTWvgHhs/$tB.MLBIPiN/M35eFdLxfM04Bbz20FIZeMONSqHqjJVA";

  k8s = {
    primaryNode = false;
  };

  networking = {
    address = "192.168.86.4";
    mainNetworkInterface = "enp0s31f6";
  };
}
