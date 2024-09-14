{ config, pkgs, ... }:

let
  zsh-config = builtins.fetchGit {
    url = "https://github.com/AidanHilt/PersonalMonorepo.git";
    ref = "feat/nixos";
    rev = "6d7d718e50368944b652fc6de4be7f483211e850"; #pragma: allowlist secret
  } + "/nix/home-manager/modules/zsh.nix";
in
{
  home-manager.users.aidan = {
    # Home Manager needs a bit of information about you and the paths it should
    # manage.
    home.homeDirectory = "/home/aidan";

    home.stateVersion = "24.11"; # Please read the comment before changing.

    imports = [
      zsh-config
    ];

    # The home.packages option allows you to install Nix packages into your
    # environment.
    home.packages = [];

    home.sessionVariables = {};

    # Let Home Manager install and manage itself.
    programs.home-manager.enable = true;
  };
}
