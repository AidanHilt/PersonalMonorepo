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

  mapA = f: attrs: with builtins; attrValues (mapAttrs f attrs);

in
{
  environment.systemPackages = with pkgs; [
    dnsmasq
  ];

  launchd.daemons.dnsmasq = {
  serviceConfig = {
    WorkingDirectory = "/var/empty";
    Program = "/bin/sh";
    ProgramArguments = [
      "/bin/sh"
      "-c"
      ''
        # Wait for nix store to be available
        while [ ! -x "${pkgs.dnsmasq}/bin/dnsmasq" ]; do
          sleep 5
        done
        exec "${pkgs.dnsmasq}/bin/dnsmasq" --listen-address=127.0.0.1 --port=53 --keep-in-foreground ${lib.concatMapStringsSep " " (domain: addr: "--address=/${lib.strings.removePrefix "*." domain}/${addr}") dnsmasqAddresses}
      ''
    ];
    KeepAlive = true;
    RunAtLoad = true;
    ThrottleInterval = 30;
  };
};

  environment.etc = builtins.listToAttrs (builtins.map (domain: {
    name = "resolver/${lib.strings.removePrefix "*." domain}";
    value = {
      enable = true;
      text = ''
        port 53
        nameserver 127.0.0.1
        '';
    };
  }) (builtins.attrNames dnsmasqAddresses));
}