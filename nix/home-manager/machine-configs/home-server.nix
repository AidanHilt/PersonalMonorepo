{ inputs, globals, pkgs, lib, system, ...}:

let
  vim-config = globals.personalConfig + "/home-manager/modules/vim.nix";
  zsh-config = globals.personalConfig + "/home-manager/modules/zsh.nix";
in

{
  imports = [
    #vim-config
    #zsh-config
  ];

  # Home Manager needs a bit of information about you and the paths it should
  # manage.

  home.stateVersion = "24.05"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [];

  home.sessionVariables = {};

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}