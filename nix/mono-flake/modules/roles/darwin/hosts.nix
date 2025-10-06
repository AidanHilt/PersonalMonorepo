{ inputs, globals, pkgs, machine-config, lib, ...}:

let
  dnsConstants = import ../universal/_hosts.nix;

  dnsmasqAddresses = lib.listToAttrs (
    lib.flatten (
      lib.mapAttrsToList (ip: hostnames:
        map (hostname: { name = hostname; value = ip; }) hostnames
      ) dnsConstants.dnsHosts
    )
  );
in

{
  environment.systemPackages = with pkgs; [
    dnsmasq
  ];

  services.dnsmasq = {
    enable = true;
    addresses = dnsmasqAddresses;
  };
}