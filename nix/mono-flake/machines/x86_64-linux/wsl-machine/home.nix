{ inputs, globals, pkgs, lib, system, machine-config, ...}:

{
  imports = [
    ../../../home-manager/shared-configs/desktop-terminal.nix
  ];

  home.stateVersion = "24.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}