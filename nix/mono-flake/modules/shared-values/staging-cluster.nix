{
  username = "aidan";

  hashedPassword = "$y$j9T$47Fj09DL3ycTvCft06SAE1$FIYj3k6p1wzVOrZI.aLp5s7IBblimqa1/k/ACv9hiC/";

  networking = {
    fixedIp = true;

    defaultGateway = "192.168.86.1";
    nameservers = [ "192.168.86.3" ];
    prefixLength = 24;

    loadBalancerIp = "192.168.86.22";
  };

  k8s = {
    clusterName = "staging-cluster";
  };
}