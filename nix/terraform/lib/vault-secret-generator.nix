{ lib, ... }:

let
  mkVaultSecret = key: value:
    let
      path     = value.auth.path or key;
      suffix   = if path != "" then "/*" else "*";
      fullPath = "${path}${suffix}";

      resolveValue = dataKey: config:
        if config ? value then
          config.value
        else if config.readFromVars or false then
          "\${var.${config.key_name or dataKey}}"
        else
          "\${random_password.${config.key_name or "${key}-${dataKey}"}.result}";

      generatedKeys = lib.filterAttrs (dataKey: config:
        !(config ? value) && !(config.readFromVars or false)
      ) (value.data or {});

      isPostgresPassword = value.postgresPassword or true;
    in {
      resource.vault_policy.${key} = {
        name   = value.auth.role_name or key;
        policy = ''
          path "${value.mount}/data/${fullPath}" {
            capabilities = ["read", "list"]
          }
          path "${value.mount}/${fullPath}" {
            capabilities = ["read", "list"]
          }
        '';
      };

      resource.vault_kubernetes_auth_backend_role.${key} = {
        backend                          = "kubernetes";
        role_name                        = value.auth.role_name or key;
        bound_service_account_names      = [ (value.service_account or key) ]
                                           ++ lib.optional (value.postgres_secret or false) "postgres-cluster";
        bound_service_account_namespaces = [ value.namespace ]
                                           ++ lib.optional (value.postgres_secret or false) "postgres";
        token_ttl                        = 3600;
        token_policies                   = [ "\${vault_policy.${key}.name}" ];
        depends_on                       = [
          "vault_auth_backend.kubernetes"
          "vault_kubernetes_auth_backend_config.backend_config"
        ];
      };

      resource.vault_kv_secret_v2.${key} = {
        mount     = "\${vault_mount.${value.mount}.path}";
        name      = value.path or "${key}/config";
        data_json = "\${jsonencode(${
          builtins.toJSON (lib.mapAttrs resolveValue value.data)
        })}";
      };

      resource.vault_mount.${value.mount} = {
        path        = value.mount;
        type        = "kv-v2";
        description = "KV v2 secrets mount for ${key}";

        options = {
          version = "2";
        };
      };

      resource.random_password = lib.mapAttrs' (dataKey: config:
        let
          passwordKey = config.key_name or "${key}-${dataKey}";
        in
        lib.nameValuePair passwordKey {
          length           = config.length or 32;
          special          = !isPostgresPassword;
          override_special = if isPostgresPassword then null else config.override_special or null;
        }
      ) generatedKeys;

      resource.vault_auth_backend.kubernetes = {
        type = "kubernetes";
        path = "kubernetes";
      };

      data.kubernetes_secret.vault_auth = {
        metadata = {
          name = "\${var.auth_secret_name}";
          namespace = "\${var.auth_secret_namespace}";
        };
      };

      resource.vault_kubernetes_auth_backend_config.backend_config = {
        backend            = "\${vault_auth_backend.kubernetes.path}";
        kubernetes_host    = "https://kubernetes.default.svc.cluster.local";
        kubernetes_ca_cert = "\${data.kubernetes_secret.vault_auth.data[\"ca.crt\"]}";
        token_reviewer_jwt = "\${data.kubernetes_secret.vault_auth.data[\"token\"]}";
      };

      variable.auth_secret_name = {
        type        = "string";
        description = "The name of the secret that stores the service account token used to run kubernetes auth";
        default     = "vault-sa-token";
      };

      variable.auth_secret_namespace = {
        type        = "string";
        description = "The namespace of the secret that stores the service account token used to run kubernetes auth";
        default     = "vault";
      };
    };

  mkVaultSecrets = secretDefinitions:
    lib.foldAttrs lib.recursiveUpdate {} (
      lib.mapAttrsToList mkVaultSecret secretDefinitions
    );

in {
  inherit mkVaultSecret mkVaultSecrets;
}