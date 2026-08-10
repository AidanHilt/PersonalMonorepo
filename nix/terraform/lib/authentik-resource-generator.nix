{ lib, ... }:

let
  mkProxyApplication = applicationName: internalHost: externalHost: environment: {authentikHostBrowser ? "", authentikApplicationName ? "", subdomain ? ""}:
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


      splitProtocol = url:
        let
          m = builtins.match "^([a-zA-Z][a-zA-Z0-9+.-]*://)(.*)$" url;
        in
        if m == null
        then { protocol = ""; rest = url; }
        else { protocol = builtins.elemAt m 0; rest = builtins.elemAt m 1; };

      # Strip everything up to and including the first dot, leaving the "base" domain
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
        else
          let
            split = splitProtocol externalHost;
            # We'll have to identify if a hostname is secure or not, and change this based on that
            protocol = "https://";
          in
          protocol + "iam." + (stripSubdomains split.rest);

      resolvedExternalHost =
        let
          # We'll have to identify if a hostname is secure or not, and change this based on that
          protocol = "https://";
        in
        if subdomain != null && subdomain != ""
        then
          let
            split = splitProtocol externalHost;
          in
          protocol + subdomain + "." + (stripSubdomains split.rest)
        else
          protocol + externalHost;

      safeExternalHost = builtins.replaceStrings ["."] ["-"] externalHost;
    in
    {
      locals = {
        "authentik_url_${safeExternalHost}" = "\${var.secure ? \"https\" : \"http\"}://\${var.authentik_subdomain}.${externalHost}";
      };

      variable = {
        "${environment}" = {
          type = "bool";
          description = "Create resources based on configuration of environment ${environment}";
          default = false;
        };
      };

      resource = {
        authentik_provider_proxy = {
          "${applicationName}_${safeExternalHost}" = {
            count = "\${var.${environment} ? 1 : 0}";
            name = "${applicationName}_${safeExternalHost}";
            internal_host = "${internalHost}";
            external_host = "${resolvedExternalHost}";
            authorization_flow = "\${data.authentik_flow.default-authorization-flow.id}";
            invalidation_flow = "\${data.authentik_flow.default-invalidation-flow.id}";
            mode = "forward_single";
            cookie_domain = ".${stripSubdomains externalHost}";
          };
        };

        authentik_application = {
          "${applicationName}_${safeExternalHost}" = {
            count = "\${var.${environment} ? 1 : 0}";
            name = resolvedApplicationName;
            slug = "${applicationName}";
            protocol_provider = "\${resource.authentik_provider_proxy.${applicationName}_${safeExternalHost}[0].id}";
          };
        };

        authentik_outpost = {
          "proxyOutpost_${safeExternalHost}" = {
            name = "proxy-outpost-${safeExternalHost}";
            count = "\${var.${environment} ? 1 : 0}";

            config = builtins.toJSON {
              authentik_host         = "http://authentik-server.authentik.svc.cluster.local";
              authentik_host_browser = "\${local.authentik_url_${safeExternalHost}}";
            };

            service_connection = "\${data.authentik_service_connection_kubernetes.default.id}";

            type = "proxy";
            protocol_providers = [
              "\${resource.authentik_provider_proxy.${applicationName}_${safeExternalHost}[0].id}"
            ];
          };
        };
      };
    };
in

{
  inherit mkProxyApplication;
}