{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ../roles/nixos/linux-universal.nix

    ../roles/nixos/desktop/gaming.nix
    ../roles/nixos/desktop/plasma-desktop.nix
    #../roles/nixos/desktop/virtual-machine.nix
    ../roles/nixos/desktop/docker.nix

    ../roles/nixos/desktop/apps/keepassxc.nix
    ../roles/nixos/desktop/apps/piper.nix

    ./linux-desktop-terminal.nix
  ];

  programs.firefox.enable = true;
}
