{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ./_generate-desktop-files.nix
    ./_generate-homelab-node-files.nix
  ];
}