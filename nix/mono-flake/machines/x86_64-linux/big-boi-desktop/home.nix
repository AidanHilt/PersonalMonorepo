{ inputs, globals, pkgs, lib, system, machine-config, ...}:

{
  imports = [
    ../../../home-manager/modules/atils.nix
    ../../../home-manager/modules/firefox.nix
    ../../../home-manager/modules/kubernetes.nix
    ../../../home-manager/modules/vim.nix
    ../../../home-manager/modules/vscode.nix
    ../../../home-manager/modules/zsh.nix
  ];

  home.stateVersion = "25.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
