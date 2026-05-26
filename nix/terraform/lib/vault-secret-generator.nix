{ lib, ... }:

let
  mkVaultSecret = key: value: {standalone ? true, appendSuffix ? true}:
    let
      path     = value.auth.path or key;
      suffix   = if !appendSuffix then "" else (if path != "" then "/*" else "*");
      fullPath = "${path}${suffix}";

      # Calculated variables

      # The name we'll use, defaults to the name of the secret item, but can be specified
      mountName = value.mount or key;

      # Setting the service accounts we'll allow. Defaults to the name of the secret item, but can be specified
      # as either a string, or as a list of strings
      serviceAccounts = if (value.serviceAccounts or "") != "" then
        (if builtins.isString value.serviceAccounts then [value.serviceAccounts] else value.serviceAccounts)
          else [key];

      # Setting the namespaces we'll allow. Defaults to the name we calculated for the mount above, but
      # can be specified as either a string, or as a list of strings
      namespaceNames = if (value.namespaces or "") != "" then
        (if builtins.isString value.namespaces then [value.namespaces] else value.namespaces)
          else [mountName];

      resolveValue = dataKey: config:
        if (builtins.isString config && config != "") then
          config
        else if config ? value then
          config.value
        else if config ? tfVar then
          "\${var.${config.tfVar.name}}"
        else
          "\${random_password.${config.key_name or "${key}-${dataKey}"}.result}";

      generatedKeys = lib.filterAttrs (dataKey: config:
        !(config ? value) && !(config ? tfVar) && !(builtins.isString config && config != "")
      ) (value.data or {});

      generatedVariables = lib.filterAttrs (dataKey: config:
        (config ? tfVar)
      ) (value.data or {});

      isPostgresPassword = value.postgresPassword or true;
    in {
      resource.vault_policy.${key} = {
        name   = value.auth.role_name or key;
        policy = ''
          path "${mountName}/data/${fullPath}" {
            capabilities = ["read", "list"]
          }
          path "${mountName}/${fullPath}" {
            capabilities = ["read", "list"]
          }
        '';
      };

      resource.vault_kubernetes_auth_backend_role.${key} = {
        backend                          = "kubernetes";
        role_name                        = value.auth.role_name or key;
        bound_service_account_names      = serviceAccounts
                                           ++ lib.optional (value.postgres_secret or false) "postgres-cluster";
        bound_service_account_namespaces = namespaceNames
                                           ++ lib.optional (value.postgres_secret or false) "postgres";
        token_ttl                        = 3600;
        token_policies                   = [ "\${vault_policy.${key}.name}" ];
        depends_on                       = lib.mkIf (standalone) [
          "vault_auth_backend.kubernetes"
          "vault_kubernetes_auth_backend_config.backend_config"
        ];
      };

      resource.vault_kv_secret_v2.${key} = {
        mount     = "\${vault_mount.${mountName}.path}";
        name      = value.path or "${key}/config";
        data_json = "\${jsonencode(${
          builtins.toJSON (lib.mapAttrs resolveValue value.data or {})
        })}";
      };

      resource.vault_mount.${mountName} = {
        path        = mountName;
        type        = "kv-v2";
        description = "KV v2 secrets mount for ${mountName}";

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

      variable = builtins.foldl' (acc: x: acc // x) {} (lib.mapAttrsToList (dataKey: config:
        {
          "${config.tfVar.name}" = lib.filterAttrs (_: v: v != null && v != "") {
            description = config.tfVar.description or null;
            default = if config.tfVar ? default then if config.tfVar.default == "" then "" else config.tfVar.default else null;
            sensitive = config.tfVar.sensitive or null;
            type = config.tfVar.type or null;
          };
        }
) generatedVariables);
    };

    mkVaultSecrets = secretDefintions:
      let
        results = builtins.attrValues (builtins.mapAttrs (key: value: mkVaultSecret key value {}) secretDefintions);
        merged = builtins.foldl' (
          acc: x: builtins.foldl' (
            acc2: k: lib.recursiveUpdate acc2 { ${k} = x.${k}; }
          ) acc (builtins.attrNames x)
        ) {} results;
      in
        merged;
in {
  inherit mkVaultSecret mkVaultSecrets;
}