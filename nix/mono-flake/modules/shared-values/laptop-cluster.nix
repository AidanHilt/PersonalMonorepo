{
  username = "aidan";

  networking = {
    fixedIp = true;

    defaultGateway = "192.168.86.1";
    nameservers = [ "192.168.86.3" ];
    prefixLength = 24;

    loadBalancerIp = "192.168.86.18";
  };

  k8s = {
    clusterName = "laptop-cluster";
  };
}