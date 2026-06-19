{ lib, ... }:

let
  mkProxyApplication = applicationName: internalHost: externalHost: {authentikHostBrowser ? "", authentikApplicationName ? ""}:
    let
      capitalize = s:
        let
          first = builtins.substring 0 1 s;
          rest = builtins.substring 1 (builtins.stringLength s - 1) s;
        in
        (lib.toUpper first) + rest;

      resolvedApplicationName =
        if authentikApplicationName != null && authentikApplicationName != ""
        then authentikApplicationName
        else capitalize applicationName;


      stripSubdomains = host:
        let
          parts = lib.splitString "." host;
        in
        if builtins.length parts <= 2
        then host
        else lib.concatStringsSep "." (lib.drop (builtins.length parts - 2) parts);

      resolvedHostBrowser =
        if authentikHostBrowser != null && authentikHostBrowser != ""
        then authentikHostBrowser
        else "iam." + (stripSubdomains externalHost);
    in
    {
      resource = {
        authentik_provider_proxy = {
          "${applicationName}" = {
            name = "${applicationName}";
            internal_host = "${internalHost}";
            external_host = "${externalHost}";
            authorization_flow = "\${data.authentik_flow.default-authorization-flow.id}";
            invalidation_flow = "\${data.authentik_flow.default-invalidation-flow.id}";
            mode = "forward_single";
          };
        };

        authentik_application = {
          "${applicationName}" = {
            name = resolvedApplicationName;
            slug = "${applicationName}";
            protocol_provider = "\${resource.authentik_provider_proxy.${applicationName}.id}";
          };
        };

        authentik_outpost = {
          mainProxyOutpost = {
            name = "proxy-outpost";

            config = builtins.toJSON {
              authentik_host         = "http://authentik-server.authentik.svc.cluster.local";
              authentik_host_browser = "${resolvedHostBrowser}";
            };

            type = "proxy";
            protocol_providers = [
              "\${resource.authentik_provider_proxy.${applicationName}.id}"
            ];
          };
        };
      };
    };
in

{

}