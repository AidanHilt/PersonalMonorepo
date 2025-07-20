{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  virtualisation.libvirtd.enable = true;
  users.users.${machine-config.username}.extraGroups = [ "libvirt" ];

  environment.systemPackages = with pkgs; [
    qemu
    vagrant
    virt-manager
  ];
}