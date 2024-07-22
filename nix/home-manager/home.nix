{ config, pkgs, ... }:

let
  zsh-config = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/AidanHilt/PersonalMonorepo/feat/nixos/nix/home-manager/modules/zsh.nix";
    sha256 = "";
  };

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

  home.file = {
    ".p10k.zsh" = {
      source = ./.p10k.zsh;
    };
  };

  home.sessionVariables = {
    # EDITOR = "emacs";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
