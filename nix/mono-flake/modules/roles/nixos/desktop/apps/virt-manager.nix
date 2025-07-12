{ inputs, globals, pkgs, machine-config, ...}:

{
  environment.systemPackages = with pkgs; [
    virt-manager
  ];
}