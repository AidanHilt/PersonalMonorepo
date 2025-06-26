{
  username = "";

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

  #   clusterEndpoint = "";
  #   # Used to identify which secrets to provide to the cluster
  #   clusterName = "";
  # };
}