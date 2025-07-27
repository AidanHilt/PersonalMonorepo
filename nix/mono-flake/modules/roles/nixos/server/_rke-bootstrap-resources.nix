{ inputs, globals, pkgs, machine-config, lib, ...}:

let 
  manifestPath = "../var/lib/rancher/rke2/server/manifests";
in

{
  environment.etc = {
    argoCD = {
      target = "${manifestPath}/argocd-helm.yaml";
      text = "test";
    };
  };
}