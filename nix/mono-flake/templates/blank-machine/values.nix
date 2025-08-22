{
  # Only uncommented values actually need to be set. See other comments for notes on values
  
  username = "aidan"; # Fuck it, it's mostly going to be me using it

  # This sets the password for the default user specified above. You don't HAVE to set it, but if you don't, you will
  # need another way to set your user's password. Only for Linux hosts, macOS machines are configured before Nix is available
  # hashedPassword = "";

  # defaultValues = $VALUES_FILE_COMMON_CONFIG_OPTIONS;

  # NOTE: You won't need to set hostname, unless you want it to be different from the name of the directory
  # hostname = "";

  # These settings are for controlling modules that are adjustable based on role, i.e. installing different extensions
  # for a work machine vs a personal one. These do not need to be set if the default value listed here is acceptable
  # configSwitches = {
  #   workMachine = false;
  #   wsl = false;
  # };

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
  # 
  #   Used for when we need a network interface, we'll assume all our machines only 
  #   have one we care about
  #   mainNetworkInterface = "enp0s1";
  # }

  # k8s = {
  #   primaryNode = false;

  #   NOTE: Either this or networking.loadBalancerIp MUST be set for RKE nodes. We should mostly be
  #   using loadBalancerIp
  #   clusterEndpoint = "";
  #   # Used to identify which secrets to provide to the cluster
  #   clusterName = "";
  # };


  # See modules/universal/rclone.nix for the real default values. You probably don't need to change this
  # rclone = {
  #   wallpaperDir = "/home/user/Wallpapers";
  #   keePassDir = "/home/user/KeePass";

  #   windowsDocumentsDir = "/mnt/d/user/Documents";
  #   windowsHomeDir = "/mnt/d/user/";
  #   windowsGHubConfigDir = "/mnt/d/user/AppData/local/LGHUB";
  # };

  # git = {
  #   email = "aidanhilt2@gmail.com";
  #   username = "ahilt";
  # };
}