# Note: For now, this is just to put our kubeconfig out, but in the future...

{ inputs, pkgs, globals, ... }:

{
  age.secrets.kubeconfig = {
    file = globals.nixConfig + "/secrets/kubeconfig.age";
    path = "/Users/${globals.username}/.kube/config";
    owner = "${globals.username}";
    mode = "700";
    symlink = false;
  };
}