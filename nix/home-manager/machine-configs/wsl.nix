{ inputs, globals, pkgs, lib, system, ...}:

let
  atils-config = globals.nixConfig + "/home-manager/modules/atils.nix"; 
  kubernetes-config = globals.nixConfig + "/home-manager/modules/kubernetes.nix";
  vim-config = globals.nixConfig + "/home-manager/modules/vim.nix";
  zsh-config = globals.nixConfig + "/home-manager/modules/zsh.nix";
in

{
  imports = [
    atils-config
    kubernetes-config
    vim-config
    zsh-config
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