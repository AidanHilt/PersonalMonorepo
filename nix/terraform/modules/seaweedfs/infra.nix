{ libFunctions, lib, ... }:

let
  standalone = false;

  masterSecret = libFunctions.mkVaultSecret "seaweedfs" {
    namespaces = ["seaweedfs"];
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
    };
  } {inherit standalone;};

  vaultProvider = import ../../lib/vault-provider.nix {inherit lib; inherit standalone;};
  kubernetesProvider = import ../../lib/kubernetes-provider.nix {inherit lib;};

  rxresu = libFunctions.mkSeaweedFsStack "rxresu" { namespaces = ["misc"]; };

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
  rxresu
  masterSecret
  static
]

