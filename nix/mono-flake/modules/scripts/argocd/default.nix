{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ./argocd-create-master-stack.nix
    ./argocd-install-argocd.nix
    ./argocd-match-master-stack.nix
  ];
}
