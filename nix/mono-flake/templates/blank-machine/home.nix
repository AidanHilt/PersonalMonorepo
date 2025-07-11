{ inputs, globals, pkgs, lib, system, machine-config, ...}:

{
  imports = [$HOME_MANAGER_COMMON_CONFIG_OPTIONS];

  home.stateVersion = "24.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}