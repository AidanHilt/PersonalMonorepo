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
          "\${var.static_vars[\"${config.key_name or dataKey}\"]}"
        else
          "\${random_password.generated[\"${config.key_name or "${key}-${dataKey}"}\"].result}";

      generatedKeys = lib.filterAttrs (dataKey: config:
        !(config ? value) && !(config.readFromVars or false)
      ) (value.data or {});

      isPostgresPassword = value.postgresPassword or true;
    in {
      resource.vault_policy.reader.${key} = {
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

      resource.vault_kubernetes_auth_backend_role.reader.${key} = {
        backend                          = "kubernetes";
        role_name                        = value.auth.role_name or key;
        bound_service_account_names      = [ (value.service_account or key) ]
                                           ++ lib.optional (value.postgres_secret or false) "postgres-cluster";
        bound_service_account_namespaces = [ value.namespace ]
                                           ++ lib.optional (value.postgres_secret or false) "postgres";
        token_ttl                        = 3600;
        token_policies                   = [ "\${vault_policy.reader[\"${key}\"].name}" ];
        depends_on                       = [
          "vault_auth_backend.kubernetes"
          "vault_kubernetes_auth_backend_config.backend_config"
        ];
      };

      resource.vault_kv_secret_v2.config.${key} = {
        mount     = "\${vault_mount.kv_mounts[\"${value.mount}\"].path}";
        name      = value.path or "${key}/config";
        data_json = "\${jsonencode(${
          builtins.toJSON (lib.mapAttrs resolveValue value.data)
        })}";
      };

      resource.random_password.generated = lib.mapAttrs' (dataKey: config:
        let
          passwordKey = config.key_name or "${key}-${dataKey}";
        in
        lib.nameValuePair passwordKey {
          length           = config.length or 32;
          special          = !isPostgresPassword;
          override_special = if isPostgresPassword then null else config.override_special or null;
        }
      ) generatedKeys;
    };

  mkVaultSecrets = secretDefinitions:
    lib.foldAttrs lib.recursiveUpdate {} (
      lib.mapAttrsToList mkVaultSecret secretDefinitions
    );

in {
  inherit mkVaultSecret mkVaultSecrets;
}