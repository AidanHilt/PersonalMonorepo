{
  username = "admin";

  hashedPassword = "$y$j9T$waeAyKsn3wxtrkoBkZ4qR/$hPuMTBz4v7EAwq65TaDj4jcjMfJtBuIqOr.Kbr1Xh90";

  k8s = {
    primaryNode = true;
    clusterEndpoint = "192.168.1.3";
    clusterName = "external-user-1-cluster";
  };

  networking = {
    fixedIp = true;
    loadbalancer = false;

    address = "192.168.1.3";
    mainNetworkInterface = "eno1";

    defaultGateway = "192.168.1.1";
    nameservers = [ "192.168.1.1" ];
    prefixLength = 24;
  };

  adguardhome.enabled = false;
}