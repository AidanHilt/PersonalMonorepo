{ inputs, globals, pkgs, lib, system, ...}:

{
  imports = [
    ../modules/vim.nix
    ../modules/zsh.nix
  ];

  home.file.".atils/update-config.env" = {
    text = ''
      UPDATE__REMOTE_BRANCH="feat/rke-secret-management"
      UPDATE__FLAKE_LOCATION="github:AidanHilt/PersonalMonorepo/feat/rke-secret-management?dir=nix/mono-flake"
    '';
  };

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