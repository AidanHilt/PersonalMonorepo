{ inputs, globals, pkgs, machine-config, lib, ...}:

let
  dnsConstants = import ../universal/_hosts.nix;

  # Convert hosts map to dnsmasq address entries
  dnsmasqAddresses = lib.flatten (
    lib.mapAttrsToList (ip: hostnames:
      map (hostname: "address=/${hostname}/${ip}") hostnames
    ) dnsConstants.dnsHosts
  );

  # Generate dnsmasq.conf content
  dnsmasqConf = pkgs.writeText "dnsmasq.conf" ''
    # Upstream DNS servers
    server=8.8.8.8
    server=8.8.4.4

    # Local domain
    domain=local
    expand-hosts

    # Cache settings
    cache-size=1000

    # Listen address
    listen-address=127.0.0.1

    # Bind to localhost only
    bind-interfaces

    # Enable wildcard/domain matching
    # This allows *.example.local style patterns
    domain-needed
    bogus-priv

    # DNS mappings (specific hosts)
    ${lib.concatStringsSep "\n" dnsmasqAddresses}

    # Wildcard DNS mappings
    ${lib.concatStringsSep "\n" dnsConstants.wildcardEntries}

    # Optional: Log queries for debugging wildcards
    # log-queries
    # log-facility=/var/log/dnsmasq-queries.log
  '';
in

{
  environment.systemPackages = with pkgs; [
    dnsmasq
  ];

  launchd.daemons.dnsmasq = {
    serviceConfig.ProgramArguments = [
      "${pkgs.dnsmasq}/bin/dnsmasq"
      "--keep-in-foreground"
      "--conf-file=${dnsmasqConf}"
    ];

    serviceConfig.KeepAlive = true;
    serviceConfig.RunAtLoad = true;
  };

  environment.etc = (builtins.map (domain: {
      name = "resolver/${domain}";
      value = {
        enable = true;
        text = ''
          port 53
          nameserver 127.0.0.1
          '';
      };
  }));
}