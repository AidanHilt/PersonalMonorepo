{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ./add_import_to_nix.nix
    ./_copy-text-to-clipboard.nix
    ./_generate-desktop-files.nix
    ./_generate-homelab-node-files.nix
    ./_modify-secrets-nix-let-statement.nix
  ];
}