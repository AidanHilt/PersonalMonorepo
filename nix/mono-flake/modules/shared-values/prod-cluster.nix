{
  username = "aidan";

  networking = {
    fixedIp = true;

    defaultGateway = "192.168.86.1";
    nameservers = [ "192.168.86.2" ];
    prefixLength = 24;

    loadBalancerIp = "192.168.86.2";
    virtualRouterId = 81;
  };

  k8s = {
    clusterName = "prod-cluster";
  };
}