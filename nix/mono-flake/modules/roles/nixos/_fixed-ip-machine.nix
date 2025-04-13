      networking = {
        defaultGateway = "192.168.86.1";
        hostName = hostname;
        nameservers = [ "192.168.86.3" ];
        interfaces.enp0s1.ipv4.addresses = [
          {
            address = "192.168.86.20";
            prefixLength = 24;
          }
        ];
      };
    }