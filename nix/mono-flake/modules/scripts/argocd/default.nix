{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
  ./pee.nix
    ./argocd-create-master-stack.nix
    ./argocd-install-argocd.nix
  ];
}
