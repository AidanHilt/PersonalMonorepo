{ inputs, globals, pkgs, machine-config, ...}:

let
  rke-config = if machine-config.k8s.primaryNode then
    {
      role = "server";
    }
  else
    {
      serverAddr = "https://${machine-config.k8s.clusterEndpoint}:9345";
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
    path = "etc/rancher/rke2/config.yaml";
    symlink = false;
    mode = "700";
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

    extraFlags = [
      "--config=/etc/rancher/rke2/config.yaml"
      "--write-kubeconfig-mode=0644"
    ];
  } // rke-config;

  # This is needed so the primary account can read rke2.yaml, and we can retrieve the config
  system.activationScripts.rke-permissions = {
    text = ''
    mkdir -p  /home/${machine-config.username}/.kube
    cp /etc/rancher/rke2/rke2.yaml /home/${machine-config.username}/.kube/rke2-kubeconfig.yaml
    chown aidan /home/${machine-config.username}/.kube/rke2-kubeconfig.yaml
    '';
  };
}