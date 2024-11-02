{ inputs, pkgs, globals, ... }:

# Grab bag of items that need to be different across OSes. Where possible, try not to use this, but some things are just too small to be worth it.

{
  programs.zsh = {
    shellAliases = {
      update = "git -C ~/PersonalMonorepo pull; darwin switch --flake ~/PersonalMonorepo/nix/mac-setup"
    };
  };
}