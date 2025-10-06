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

    launchd.daemons.dnsmasq = {
      serviceConfig.workingDirectory = "/etc/dnsmasq";

      serviceConfig.ProgramArguments = [
        "${pkgs.dnsmasq}/bin/dnsmasq"
        "--listen-address=127.0.0.1"
        "--port=53"
        "--keep-in-foreground"
      ] ++ (mapA (domain: addr: "--address=/${domain}/${addr}") dnsmasqAddresses);

      serviceConfig.KeepAlive = true;
      serviceConfig.RunAtLoad = true;
    };

    environment.etc = builtins.listToAttrs (builtins.map (domain: {
      name = "resolver/${domain}";
      value = {
        enable = true;
        text = ''
          port 53
          nameserver 127.0.0.1
          '';
      };
    }) (builtins.attrNames dnsmasqAddresses));
}