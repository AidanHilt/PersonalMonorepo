{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ./_generate-desktop-files.nix
    ./_generate-homelab-node-files.nix
  ];
}