{
  username = "";

  # defaultValues = $VALUES_FILE_COMMON_CONFIG_OPTIONS;

  # NOTE: You won't need to set hostname, unless you want it to be different from the name of the directory
  # hostname = "";

  # networking = {
  #   fixedIp = false;

  #   defaultGateway = "";
  #   nameservers = [];
  #   address = "";
  #   prefixLength = 24;

  #   We use keepalived to serve k8s and our DNS provider, as well as other goodies
  #   Note that this is not the kubernetes load balancer IP that serves most of our services
  #   That isn't configured here (but maybe we can note it?)
  #   loadBalancerIp = "";
  # }

  # k8s = {
  #   primaryNode = false;

  #   NOTE: Either this or networking.loadBalancerIp MUST be set for RKE nodes. We should mostly be
  #   using loadBalancerIp
  #   clusterEndpoint = "";
  #   # Used to identify which secrets to provide to the cluster
  #   clusterName = "";
  # };
}