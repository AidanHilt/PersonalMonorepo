{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  environment.systemPackages = with pkgs; [
    qemu
    vagrant
    virt-manager
  ];

  virtualisation.libvirtd = {
    enable = true;
    allowedBridges = ["enp4s0"];
  };

  users.users.${machine-config.username}.extraGroups = [ "libvirtd" ];
}