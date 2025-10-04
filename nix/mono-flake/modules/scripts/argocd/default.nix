{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
  ./  poo.nix
  ./pee.nix
    ./argocd-create-master-stack.nix
    ./argocd-install-argocd.nix
  ];
}
