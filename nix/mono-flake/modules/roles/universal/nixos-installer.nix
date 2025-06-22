{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ./_kubernetes-admin.nix
    ./_shell-script-lib.nix

    ../../scripts/nixos-key-retrieval.nix
    ../../scripts/nixos-kubeconfig-retrieval.nix
    ../../scripts/nixos-remote-install.nix
  ];
}