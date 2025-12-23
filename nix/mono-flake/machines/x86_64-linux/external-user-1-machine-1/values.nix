{
  username = "admin";

  hashedPassword = "$y$j9T$waeAyKsn3wxtrkoBkZ4qR/$hPuMTBz4v7EAwq65TaDj4jcjMfJtBuIqOr.Kbr1Xh90";

  k8s = {
    primaryNode = true;
  };

  networking = {
    fixedIp = false;
    loadbalancer = false;

    address = "192.168.86.40";
    mainNetworkInterface = "eno1";

    defaultGateway = "192.168.86.1";
    nameservers = [ "192.168.86.2" ];
    prefixLength = 24;
  };

  k8s = {
    clusterName = "prod-cluster";
    clusterEndpoint = "192.168.86.56";
  };
}