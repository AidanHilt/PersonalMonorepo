{ libFunctions, lib, inputs, pkgs, ... }:

let
  standalone = false;
  static = {
    variable = {
      authentik_access_url = {
        type        = "string";
        description = "The URL to connect to Authentik, which may be different from the URL users connect with";
      };

      authentik_token = {
        type        = "string";
        description = "The token to authenticate to Authentik";
      };

      authentik_insecure = {
        type        = "bool";
        description = "Whether or not to force an https connection";
        default     = true;
      };
      authentik_subdomain = {
        type        = "string";
        description = "The subdomain authentik is served from for the user";
        default     = "iam";
      };
      secure = {
        type        = "bool";
        description = "Use https:// for user-accessible URL if true, http:// otherwise";
        default     = true;
      };
    };

    terraform.required_providers.authentik = {
      source = "goauthentik/authentik";
      version = "2026.2.0";
    };

    provider = {
      authentik = {
        url      = "\${var.authentik_access_url}";
        token    = "\${var.authentik_token}";
        insecure = "\${var.authentik_insecure}";
      };
    };

    data = {
      authentik_flow = {
        default-authorization-flow = {
          slug = "default-provider-authorization-implicit-consent";
        };
        default-invalidation-flow = {
          slug = "default-invalidation-flow";
        };
      };
      authentik_service_connection_kubernetes = {
        default =  {
          name = "Local Kubernetes Cluster";
        };
      };
    };
  };

  mergedValues = libFunctions.loadMergedValues "istio-ingress-config";

  isIp = hostname: builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" hostname != null;

  results = builtins.concatLists
    (lib.mapAttrsToList
      (environment: value:
        builtins.concatMap
          (hostname:
            builtins.filter (x: x != null)
              (lib.mapAttrsToList
                (key: entry:
                  if hasEnabledAuthProxy entry
                  then libFunctions.mkProxyApplication key "http://${entry.destinationSvc}" hostname environment {subdomain = entry.subdomain or "";}
                  else null
                )
                value
              )
          )
          (builtins.filter (h: !(isIp h)) value.hostnames)
      )
      mergedValues
    );

  hasEnabledAuthProxy = entry:
    (entry.auth or { }).proxy.enabled or false == true;

  vaultProvider = import ../../lib/vault-provider.nix {inherit lib; inherit standalone;};
in

lib.mkMerge [
  vaultProvider
  static
  (lib.mkMerge results)
]