{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [];

  environment.systemPackages = with pkgs; [
    keepassxc
  ];
}