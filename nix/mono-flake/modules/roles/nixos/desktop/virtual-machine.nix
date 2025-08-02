{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  environment.systemPackages = with pkgs; [
    qemu
    virt-manager
  ];

  environment.variables = {
    LIBVIRT_DEFAULT_URI="qemu:///system";
  };

  networking = {
    # useNetworkd = true;
    # networkmanager.enable = lib.mkForce false;
    interfaces.${machine-config.networking.mainNetworkInterface}.useDHCP = false;
    interfaces.br0.useDHCP = true;
   
    bridges = {
      "br0" = {
        interfaces = [ "${machine-config.networking.mainNetworkInterface}" ];
      };
    };
  };

  virtualisation.libvirtd = {
    enable = true;
    allowedBridges = ["br0"];
  };

  users.users.${machine-config.username}.extraGroups = [ "libvirtd" ];
}