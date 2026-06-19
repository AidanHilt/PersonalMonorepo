{ libFunctions, lib, ... }:

let
  standalone = false;
  static = {
    variable = {
      authentik_url = {
        type        = "string";
        description = "The URL to connect to Authentik";
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
    };

    terraform.required_providers.authentik = {
      source = "goauthentik/authentik";
      version = "2026.2.0";
    };

    provider = {
      authentik = {
        url      = "\${var.authentik_url}";
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

    # resource = {
    #   authentik_service_connection_kubernetes = {
    #     local = {
    #       name = "local";
    #       local = true;
    #     };
    #   };
    # };
  };

  prowlarr = libFunctions.mkProxyApplication "prowlarr" "http://prowlarr.videos.svc.cluster.local" "http://qa-cluster-lb.lan" {};

  vaultProvider = import ../../lib/vault-provider.nix {inherit lib; inherit standalone;};
in

lib.mkMerge [
  vaultProvider
  static
  prowlarr
]