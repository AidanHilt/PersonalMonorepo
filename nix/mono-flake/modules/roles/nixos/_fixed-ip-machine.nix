{ inputs, globals, pkgs, machine-config, ...}:


{
  networking = mkIf ${machine-config.networking.fixedIp} {
    defaultGateway = ${machine-config.networking.gateway};
    nameservers = ${machine-config.networking.nameservers};
    interfaces.enp0s1.ipv4.addresses = [
      {
        address = ${machine-config.networking.address};
        prefixLength = ${machine-config.networking.prefixLength};
      }
    ];
  };
}


