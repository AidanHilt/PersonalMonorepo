{
  username = "aidan";

  hostname = "nixos";

  hashedPassword = "$y$j9T$MuEfVxt2pLFnFXKd9Pc/A.$HKm4EUNJjLMB2NP43OEGZTBNHdj267OxMmkaA6aCTn9";

  secretMachine = false;

  networking = {
    fixedIp = true;
    address = "192.168.86.24";

    defaultGateway = "192.168.86.1";
    nameservers = [ "192.168.86.2" ];
    prefixLength = 24;
  };
}
