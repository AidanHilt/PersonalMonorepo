{ inputs, globals, pkgs, machine-config, ...}:

{
  environment.systemPackages = with pkgs; [
    vagrant
    virt-manager
  ];
}