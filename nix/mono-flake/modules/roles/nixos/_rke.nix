{ inputs, globals, pkgs, machine-config, ...}:

let
  clusterEndpoint = if machine-config.k8s.clusterEndpoint then machine-config.k8s.clusterEndpoint else machine.config.networking.loadBalancerIp;

  rkeConfig = if machine-config.k8s.primaryNode then
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
    mode = "400";
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
      "--write-kubeconfig-mode=0640"
      "--advertise-address=${machine-config.networking.address}"
      "--tls-san=${clusterEndpoint}"
    ];
  } // rkeConfig;

  systemd.services.fix-kubeconfig-permissions = pkgs.lib.mkIf (machine-config.k8s.primaryNode) {
    description = "Fix kubeconfig permissions";
    after = [ "rke2-server.service" ]; # adjust service name as needed
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if [ -f /etc/rancher/rke2/rke2.yaml ]; then
        chgrp sensitive-file-readers /etc/rancher/rke2/rke2.yaml
      fi
    '';
  };
}