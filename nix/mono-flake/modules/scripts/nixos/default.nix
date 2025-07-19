{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ./nixos-hardware-config-retrieval.nix
    ./nixos-key-retrieval.nix
    ./nixos-kubeconfig-retrieval.nix
    ./nixos-remote-install.nix
    ./nixos-build-aarch64-iso.nix
    ./nixos-build-x86_64-iso.nix
  ];
}