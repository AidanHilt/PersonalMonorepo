# This stores common configuration for running kubernetes. Note that this will not have shell configurations, as we like doing those in Home Manager.
# That configuration is located here:


{ inputs, pkgs, globals, ... }:

# Let's just leave this here for now. It won't decrypt on the work laptop, and I don't think it stops the total upgrade from going through.
# TODO fix kubeconfig secrets
# Just in case that doesn't work, or it gets really annoying
{
  age.secrets.kubeconfig = {
    file = globals.nixConfig + "/secrets/kubeconfig.age";
    path = "/Users/${globals.username}/.kube/config";
    owner = "${globals.username}";
    mode = "700";
    symlink = false;
  };

  environment.systemPackages = [
    pkgs.kubectl
    pkgs.k9s
    pkgs.kubecm
    pkgs.kubernetes-helm
  ];
}