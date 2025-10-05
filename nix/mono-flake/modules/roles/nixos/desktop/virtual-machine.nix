{ inputs, globals, pkgs, machine-config, lib, ...}:

let
  isFixedIp = machine-config.networking.fixedIp or false;

  networkingConfig = if isFixedIp then {
    # useNetworkd = true;
    # networkmanager.enable = lib.mkForce false;
    interfaces.br0.useDHCP = false;

    interfaces.${machine-config.networking.mainNetworkInterface} = lib.mkForce {
      useDHCP = false;
    };

    interfaces.br0.ipv4.addresses = [
      {
        address = machine-config.networking.address;
        prefixLength = machine-config.networking.prefixLength;
      }
    ];

    bridges = {
      "br0" = {
        interfaces = [ "${machine-config.networking.mainNetworkInterface}" ];
      };
    };
  }

  else {
    # useNetworkd = true;
    # networkmanager.enable = lib.mkForce false;
    #interfaces.${machine-config.networking.mainNetworkInterface}.useDHCP = false;
    interfaces.br0.useDHCP = true;

    bridges = {
      "br0" = {
        interfaces = [ "${machine-config.networking.mainNetworkInterface}" ];
      };
    };
  };
in

{
  environment.systemPackages = with pkgs; [
    qemu
    virt-manager
  ];

  environment.variables = {
    LIBVIRT_DEFAULT_URI="qemu:///system";
  };

  networking = networkingConfig;

  virtualisation.libvirtd = {
    enable = true;
    allowedBridges = ["br0"];
  };

  users.users.${machine-config.username}.extraGroups = [ "libvirtd" ];
}