{ inputs, globals, pkgs, machine-config, lib, ...}:

let
  dnsConstants = import ../universal/_hosts.nix;

  # Convert hosts map to dnsmasq address entries
  # Each IP can have multiple hostnames
  dnsmasqAddresses = lib.flatten (
    lib.mapAttrsToList (ip: hostnames:
      map (hostname: "address=/${hostname}/${ip}") hostnames
    ) dnsConstants.dnsHosts
  );
in
{
  services.dnsmasq = {
    enable = true;
    settings = {

      server = [
        "8.8.8.8"
        "8.8.4.4"
      ];

      domain = "local";
      expand-hosts = true;

      address = dnsmasqAddresses;
    };
  };
}