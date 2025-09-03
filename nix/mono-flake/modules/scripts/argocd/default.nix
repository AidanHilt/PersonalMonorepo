{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ./argocd-create-master-stack.nix
  ];
}