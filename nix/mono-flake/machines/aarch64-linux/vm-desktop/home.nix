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

  # Home Manager needs a bit of information about you and the paths it should
  # manage.

  home.stateVersion = "24.11"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [];

  home.sessionVariables = {};

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}