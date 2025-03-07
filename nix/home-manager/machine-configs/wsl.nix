{ inputs, globals, pkgs, lib, system, ...}:

let
  vim-config = globals.nixConfig + "/home-manager/modules/vim.nix";
  zsh-config = globals.nixConfig + "/home-manager/modules/zsh.nix";
in

{
  imports = [
    vim-config
    zsh-config
    "${fetchTarball "https://github.com/msteen/nixos-vscode-server/tarball/master"}/modules/vscode-server/home.nix"
  ];

  # Home Manager needs a bit of information about you and the paths it should
  # manage.

  home.stateVersion = "24.11"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [];

  home.sessionVariables = {};

  services.vscode-server.enable = true;

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}