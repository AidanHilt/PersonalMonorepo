{ libFunctions, lib, ... }:

let
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
      };
    };
  };

in

lib.mkMerge [

]