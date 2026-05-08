{ libFunctions, lib, ... }:

let
  masterSecret = libFunctions.mkVaultSecret "seaweedfs" {
    #serviceAccounts = "seaweedfs";
    namespace = ["seaweedfs"];
    #mount = "seaweedfs";
    postgres_secret = false;
    data = {
      accessKey = {
        tfVar = {
          name        = "access_key";
          type        = "string";
          description = "The pre-existing access key for seaweedfs with admin privileges";
        };
      };
      secretKey = {
        tfVar = {
          type        = "string";
          name        = "secret_key";
          description = "The pre-existing secret key for seaweedfs with admin privileges";
          sensitive   = true;
        };
      };
      seaweedfs_s3_config = ''
          {
            "identities": [
              {
                "name": "admin",
                "credentials": [
                  {
                    "accessKey": "''${var.access_key}",
                    "secretKey": "''${var.secret_key}"
                  }
                ],
                "actions": ["Admin", "Read", "Write", "List", "Tagging"]
              }
            ]
          }
        '';
    };
  };

  seaweedfsConfig = libFunctions.mkSeaweedFsBucket "test";

  vaultProvider = import ../../lib/vault-provider.nix {inherit lib;};
  kubernetesProvider = import ../../lib/kubernetes-provider.nix {inherit lib;};

  static = {
    variable = {
      seaweedfs_endpoint = {
        type        = "string";
        description = "The endpoint for the seaweedfs S3 API";
        default     = "http://localhost:8333";
      };
    };

    terraform.required_providers.seaweedfs = {
      source  = "JonasKop/seaweedfs";
      version = "0.2.0";
    };

    provider.seaweedfs = {
      endpoint   = "\${var.seaweedfs_endpoint}";
      insecure   = true;
      access_key = "\${var.access_key}";
      secret_key = "\${var.secret_key}";
    };
  };
in

lib.mkMerge [
  vaultProvider
  kubernetesProvider
  masterSecret
  seaweedfsConfig
  static
]

