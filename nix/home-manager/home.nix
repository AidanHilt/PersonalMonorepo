{ inputs, globals, pkgs, lib, system, ...}:

let
  extensions =
    (import (builtins.fetchGit {
      url = "https://github.com/nix-community/nix-vscode-extensions";
      ref = "refs/heads/master";
      rev = "c43d9089df96cf8aca157762ed0e2ddca9fcd71e"; #pragma: allowlist secret
    })).extensions.${system};

  # vscode-config = globals.personalConfig + "/home-manager/modules/vscode.nix";
  # firefox-config = globals.personalConfig + "/home-manager/modules/firefox.nix";
  # vim-config = globals.personalConfig + "/home-manager/modules/vim.nix";
in

{
  # imports = [
  #   vscode-config
  #   firefox-config
  #   vim-config
  # ];

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