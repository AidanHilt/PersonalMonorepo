{
  username = "aidan";

  hashedPassword = "$y$j9T$DyVME0er7DkVB1COSv8ca1$kjBax/3mYwsK2di4XFqsYSCoE3Ueok6yhjhMo4Q0pu/";

  networking = {
    fixedIp = true;

    defaultGateway = "192.168.86.1";
    nameservers = [ "192.168.86.2" ];
    prefixLength = 24;

    address = "192.168.86.40";
    mainNetworkInterface = "enp4s0";
  };
}
