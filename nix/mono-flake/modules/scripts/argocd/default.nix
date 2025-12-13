{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ./argocd-match-master-stack.nix
    ./argocd-create-master-stack.nix
    ./argocd-install-argocd.nix
  ];
}
