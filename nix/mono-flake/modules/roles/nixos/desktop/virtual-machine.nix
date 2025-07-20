{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  environment.systemPackages = with pkgs; [
    qemu
    vagrant
    virt-manager
  ];

  networking = {
    # Create the bridge interface
    bridges = {
      "br0" = {
        interfaces = [ "enp4s0" ];  # Replace with your physical interface name
      };
    };
  };

  virtualisation.libvirtd = {
    enable = true;
    allowedBridges = ["br0"];
  };

  users.users.${machine-config.username}.extraGroups = [ "libvirtd" ];
}