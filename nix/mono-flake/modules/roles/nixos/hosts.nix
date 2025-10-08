{ inputs, globals, pkgs, machine-config, lib, ...}:

let
  dnsConstants = import ../universal/_hosts.nix;
in
{
  networking.hosts = dnsConstants.dnsHosts;
}
