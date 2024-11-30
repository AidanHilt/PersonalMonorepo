{ inputs, globals, pkgs, ...}:

{
  environment.systemPackages = [
    pkgs.rke2
  ];

  services.rke2 = {
    enable = true;
    role = "server";

    cni = "calico";
  };

  networking.firewall = {
    # See https://docs.rke2.io/install/requirements#inbound-network-rules for details
    allowedTCPPorts = [ 6443 6444 9345 10250 2379 2380 2381 ];
    allowedTCPPortRanges = [
      {
        from = 30000;
        to = 32767;
      }
    ];
  };

  age.secrets.rke-token = {
    file = globals.nixConfig + "/secrets/rke-token-mac-cluster.age";
    path = "/var/lib/rancher/rke2/server/node-token";
    owner = "aidan";
    mode = "744";
  };
}