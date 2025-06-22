{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ../../scripts/nixos-key-retrieval.nix
    ../../scripts/nixos-kubeconfig-retrieval.nix
    ../../scripts/nixos-remote-install.nix
    ../../scripts/nixos-hardware-config-retrieval.nix

    ../../scripts/mono-flake-new-machine.nix
    ../../scripts/mono-flake-new-script.nix
  ];
}