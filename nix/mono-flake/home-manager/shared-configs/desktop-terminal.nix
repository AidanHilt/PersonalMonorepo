{ inputs, globals, pkgs, lib, system, machine-config, ...}:

{
  imports = [
    ../modules/vim.nix
    ../modules/zsh.nix
    ../modules/kubernetes.nix
  ];

  # TODO Let's see if we can read in PERSONAL_MONOREPO_LOCATION some other way
  home.file.".atils/update-config.env" = {
    text = ''
      UPDATE__FLAKE_LOCATION="/${machine-config.userBase}/${machine-config.username}/PersonalMonorepo/nix/mono-flake"
      UPDATE__MACHINE_NAME="${machine-config.hostname}"
    '';
  };

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [];

  home.sessionVariables = {};

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}