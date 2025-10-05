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
  networking.hosts = dnsConstants.dnsHosts;
}