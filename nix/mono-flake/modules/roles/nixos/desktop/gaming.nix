{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [];

  environment.systemPackages = with pkgs; [
    discord
    inputs.parsecgaming.packages.${pkgs.system}.parsecgaming
  ];

  programs.steam = {
    enable = true;
  };
}