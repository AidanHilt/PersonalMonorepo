# Note: For now, this is just to put our kubeconfig out, but in the future...

{ inputs, pkgs, globals, ... }:

{

  # TODO let's try and get this set up right, right now the permissions are fucked
  # Maybe we need a ticket?
  age.secrets.kubeconfig = {
    file = ../secrets/kubeconfig.age;
    path = "/Users/${globals.username}/.kube/config";
    owner = "${globals.username}";
    group = "${globals.username}";
    mode = "744";
  };
}