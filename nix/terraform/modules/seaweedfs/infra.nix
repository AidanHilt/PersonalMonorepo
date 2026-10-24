{ libFunctions, lib, ... }:

let
  standalone = false;

  vaultProvider = import ../../lib/vault-provider.nix {
    inherit lib;
    inherit standalone;
  };
  kubernetesProvider = import ../../lib/kubernetes-provider.nix { inherit lib; };

  # vault-config is the source of truth for which services get a seaweedfs
  # stack: the "seaweedfs" entry itself (enabled: true) gets the admin
  # master secret, and any entry with seaweedfsSecret.enabled: true gets a
  # bucket + IAM user + vault secret (currently rxresu and tandoor). Nothing
  # here hardcodes a service list.
  vaultConfigValues = libFunctions.loadMergedValues "vault-config";
  environments = lib.filterAttrs (envName: _: envName != "original") vaultConfigValues;

  # Pre-existing admin access_key/secret_key for the seaweedfs instance,
  # stored in vault under the "seaweedfs" mount, created per environment
  # where vault-config's `seaweedfs.enabled` is true.
  mkMasterSecret =
    envName: envValues:
    if (envValues.seaweedfs.enabled or false) then
      libFunctions.mkVaultSecret "seaweedfs" {
        namespaces = [ "seaweedfs" ];
        data = {
          accessKey = {
            tfVar = {
              name = "access_key";
              type = "string";
              description = "The pre-existing access key for seaweedfs with admin privileges";
            };
          };
          secretKey = {
            tfVar = {
              type = "string";
              name = "secret_key";
              description = "The pre-existing secret key for seaweedfs with admin privileges";
              sensitive = true;
            };
          };
        };
      } envName { inherit standalone; }
    else
      { };

  mkStacksForEnv =
    envName: envValues:
    let
      seaweedfsBackedEntries = lib.filterAttrs (
        _: value: (value.seaweedfsSecret.enabled or false) == true
      ) envValues;
    in
    builtins.attrValues (
      builtins.mapAttrs (
        key: value:
        libFunctions.mkSeaweedFsStack key envName {
          namespaces = value.namespaces or [ ];
          serviceAccounts = value.serviceAccounts or [ ];
          mount = value.mount or null;
        }
      ) seaweedfsBackedEntries
    );

  masterSecrets = builtins.attrValues (builtins.mapAttrs mkMasterSecret environments);
  stacks = lib.flatten (builtins.attrValues (builtins.mapAttrs mkStacksForEnv environments));

  static = {
    variable = {
      seaweedfs_endpoint = {
        type = "string";
        description = "The endpoint for the seaweedfs S3 API";
        default = "http://localhost:8333";
      };
    };

    terraform.required_providers.seaweedfs = {
      source = "JonasKop/seaweedfs";
      version = "0.2.0";
    };

    provider.seaweedfs = {
      endpoint = "\${var.seaweedfs_endpoint}";
      insecure = true;
      access_key = "\${var.access_key}";
      secret_key = "\${var.secret_key}";
    };
  };
in

lib.mkMerge (
  [
    vaultProvider
    kubernetesProvider
    static
  ]
  ++ masterSecrets
  ++ stacks
)
