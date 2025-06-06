{ inputs, globals, pkgs, machine-config, ...}:

# TODO Let's add a with statement here
{
  networking = pkgs.lib.mkIf machine-config.networking.fixedIp {
    defaultGateway = machine-config.networking.defaultGateway;
    nameservers = machine-config.networking.nameservers;
    interfaces.enp0s1.ipv4.addresses = [
      {
        address = machine-config.networking.address;
        prefixLength = machine-config.networking.prefixLength;
      }
    ];
  };
}


