{ inputs, globals, pkgs, machine-config, lib, ...}:

let 
  argocdManifest = pkgs.writeText "argocd-helm.yaml" "test";

  manifestPath = "/var/lib/rancher/rke2/server/manifests";
in

{
 systemd.tmpfiles.rules = [
  "L ${manifestPath}/argocd-helm.yaml - - - - ${argocdManifest}"
 ]; 
}