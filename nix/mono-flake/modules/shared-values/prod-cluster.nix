{
  username = "aidan";

  networking = {
    fixedIp = true;

    defaultGateway = "192.168.86.1";
    nameservers = [ "192.168.86.13" ];
    prefixLength = 24;

    loadBalancerIp = "192.168.86.13";
  };

  k8s = {
    clusterName = "prod-cluster";
  };
}