{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ./nixos-hardware-config-retrieval.nix
    ./nixos-key-retrieval.nix
    ./nixos-kubeconfig-retrieval.nix
    ./nixos-remote-install.nix
  ];
}