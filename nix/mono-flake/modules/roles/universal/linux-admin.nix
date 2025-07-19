{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ../../scripts/system-tasks/default.nix
  ];

  environment.systemPackages = with pkgs; [

  ];
}