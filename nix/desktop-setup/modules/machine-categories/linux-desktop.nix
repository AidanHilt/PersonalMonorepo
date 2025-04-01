{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ./linux-universal.nix

    ../roles/nixos/deepin-desktop.nix
  ];

  programs.nix-ld.enable = true;
}
