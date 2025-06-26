{
  username = "aidan";

  networking = {
    fixedIp = true;

    defaultGateway = "192.168.86.1";
    nameservers = [ "192.168.86.3" ];
    prefixLength = 24;

    loadBalancerIp = 192.168.86.19
  };

  k8s = {
    clusterEndpoint = "192.168.86.20";
    # Used to identify which secrets to provide to the cluster
    clusterName = "laptop-cluster";
  };
}