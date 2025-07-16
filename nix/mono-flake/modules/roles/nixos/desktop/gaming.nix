{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [];

  environment.systemPackages = with pkgs; [
    discord
    parsec-bin
  ];

  programs.steam = {
    enable = true;
  };
}