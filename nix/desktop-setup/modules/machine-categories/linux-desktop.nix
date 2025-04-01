{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ./linux-universal

    ../roles/nixos/deepin-desktop
  ];

  programs.nix-ld.enable = true;
}
