# Note: For now, this is just to put our kubeconfig out, but in the future...

{ inputs, pkgs, globals, ... }:

{

  # TODO let's try and get this set up right, right now the permissions are fucked
  # Maybe we need a ticket?
  age.secrets.kubeconfig = {
    file = globals.nixConfig + "/secrets/kubeconfig.age";
    path = "/Users/${globals.username}/.kube/config";
    owner = "${globals.username}";
    mode = "700";
    symlink = false;
  };
}