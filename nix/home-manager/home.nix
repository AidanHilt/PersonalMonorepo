{ config, pkgs, ... }:

let
  zsh-config = builtins.fetchFromGitHub {
    owner = "AidanHilt";
    repo = "PersonalMonorepo";
    rev = "feat/nixos";
  } + "nix/home-manager/modules/zsh.nix";
in
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "aidan";
  home.homeDirectory = "/home/aidan";

  home.stateVersion = "24.05"; # Please read the comment before changing.

  imports = [
    zsh-config
  ];

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [];

  home.sessionVariables = {
    # EDITOR = "emacs";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
