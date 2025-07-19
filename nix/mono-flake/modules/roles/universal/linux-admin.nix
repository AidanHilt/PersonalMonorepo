{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ../../scripts/system-tasks/default.nix
  ];

  environment.systemPackages = with pkgs; [

  ];
}