{
  defaultValues = "prod-cluster";

  hashedPassword = "$y$j9T$4pKwnpW6t2PRzRC6pdcXA0$Y.f6EEaq.kbUzqzrrnWDxQiXgbSbdcLWGjtuFlDp.F6";

  k8s = {
    primaryNode = true;
  };

  networking = {
    address = "192.168.86.6";
    mainNetworkInterface = "enp0s20f0u2c2";
  };
}
