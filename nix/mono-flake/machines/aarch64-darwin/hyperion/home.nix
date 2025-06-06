{ inputs, globals, pkgs, lib, system, ...}:

{
  imports = [
    ../../../home-manager/modules/atils.nix
    ../../../home-manager/modules/firefox.nix
    ../../../home-manager/modules/kubernetes.nix
    ../../../home-manager/modules/vim.nix
    ../../../home-manager/modules/vscode.nix
    ../../../home-manager/modules/zsh.nix
  ];

  home.stateVersion = "24.11"; # Please read the comment before changing.

  programs.home-manager.enable = true;
}