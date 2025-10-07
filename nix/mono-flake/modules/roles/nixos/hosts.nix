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

    parseWildcardEntry = entry:
    let
      parts = builtins.match "address=/\\*\\.([^/]+)/([0-9.]+)" entry;
    in
    if parts != null then
      { domain = builtins.elemAt parts 0; ip = builtins.elemAt parts 1; }
    else
      null;

  groupByIp = entries:
    let
      parsed = builtins.filter (x: x != null) (map parseWildcardEntry entries);

      addToGroups = groups: entry:
        let
          existingDomains = groups.${entry.ip} or [];
        in
        groups // {
          entry.ip = existingDomains ++ [ entry.domain ];
        };
    in
    builtins.foldl' addToGroups {} parsed;

  wildcardEntriesToHosts = entries: groupByIp dnsConstants.wildcardEntries;
in
{
  networking.hosts = dnsConstants.dnsHosts // wildcardEntriesToHosts{};
}
