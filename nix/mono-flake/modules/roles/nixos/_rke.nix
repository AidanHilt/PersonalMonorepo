{ inputs, globals, pkgs, machine-config, ...}:

let
  rke-config = if machine-config.k8s.primaryNode then
    {
      serverAddr = "https://${machine-config.k8s.clusterEndpoint}:9345";
    }

  else
    {
      role = "server";
    };
in

{
  imports = [
    ./_longhorn.nix
  ];

  environment.systemPackages = with pkgs; [
    rke2
  ];

  age.secrets.rke-token = {
    file = ../../../secrets/rke-config-${machine-config.k8s.clusterName}.age;
    path = "/etc/default/rke2";
    symlink = false;
    mode = "444";
  };

  networking.firewall = {
    # See https://docs.rke2.io/install/requirements#inbound-network-rules for details
    allowedTCPPorts = [ 6443 6444 9345 10250 2379 2380 2381 9099 5473 ];
    allowedTCPPortRanges = [
      {
        from = 30000;
        to = 32767;
      }
    ];
  };

  services.rke2 = {
    enable = true;
    cni = "calico";
  } // rke-config;
}