{ inputs, globals, pkgs, ...}:

{
  services.rke2 = {
    enable = true;
    role = "server";

    cni = "calico";
  };
}