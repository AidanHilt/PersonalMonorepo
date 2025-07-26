{
  username = "aidan";

  hashedPassword = "$y$j9T$NExycssJl7999hLxnHVMj1$.Uyev45lQmbqVICYQX.GMv5sgTDrOLaNkARAWRLAP7.";

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