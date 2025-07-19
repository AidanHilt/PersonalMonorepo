{ inputs, globals, pkgs, machine-config, ...}:

{
  virtualisation.libvirtd.enable = true;
  users.users.${machine-config.username}.extraGroups = [ "libvirtd" ];

  environment.systemPackages = with pkgs; [
    qemu
    vagrant
    virt-manager
  ];
}