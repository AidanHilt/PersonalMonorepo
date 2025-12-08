{
  hashedPassword = "$y$j9T$4pKwnpW6t2PRzRC6pdcXA0$Y.f6EEaq.kbUzqzrrnWDxQiXgbSbdcLWGjtuFlDp.F6";


}

{
  username = "admin";

  k8s = {
    primaryNode = true;
  };

  networking = {
    fixedIp = true;
    loadbalancer = false;

    address = "192.168.86.40";
    mainNetworkInterface = "eno1";

    defaultGateway = "192.168.86.1";
    nameservers = [ "192.168.86.2" ];
    prefixLength = 24;
  };

  k8s = {
    clusterName = "prod-cluster";
  };
}