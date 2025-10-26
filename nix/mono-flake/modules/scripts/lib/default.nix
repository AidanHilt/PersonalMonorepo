{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ./_modify-secret-values.nix
    ./_edit-yaml-in-place.nix
    ./_copy-text-to-clipboard.nix
    ./_generate-desktop-files.nix
    ./_generate-homelab-node-files.nix
    ./_modify-secrets-nix-let-statement.nix
  ];
}
