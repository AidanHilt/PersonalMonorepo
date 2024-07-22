{ config, pkgs, ... }:

let
  zsh-config = builtins.fetchurl {
    url = "https://raw.githubusercontent.com/AidanHilt/PersonalMonorepo/feat/nixos/nix/home-manager/modules/zsh.nix";
    sha256 = "1f0vj9d6vqpxl9nzlmyz8wjyip1mza4vmsgbzsf9k75kmnmmdif7";
  };
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
