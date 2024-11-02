{ inputs, globals, pkgs, lib, system, ...}:

let
  atils-config = globals.personalConfig + "/home-manager/modules/atils.nix";
  firefox-config = globals.personalConfig + "/home-manager/modules/firefox.nix";
  vim-config = globals.personalConfig + "/home-manager/modules/vim.nix";
  vscode-config = globals.personalConfig + "/home-manager/modules/vscode.nix";
  zsh-config = globals.personalConfig + "/home-manager/modules/zsh.nix";
in

{
  imports = [
    atils-config
    firefox-config
    vim-config
    vscode-config
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