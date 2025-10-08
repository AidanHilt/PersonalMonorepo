{ inputs, globals, pkgs, machine-config, lib, ...}:

let
  dnsConstants = import ../universal/_hosts.nix;

  # Convert hosts map to dnsmasq address entries
  # Each IP can have multiple hostnames
in
{
  networking.hosts = dnsConstants.dnsHosts // dnsConstants.wildcardEntries;
}
