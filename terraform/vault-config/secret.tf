resource "vault_policy" "reader" {
  for_each = local.secret_definitions

  name = try(each.value.auth.role_name, each.key)

  policy = <<EOT
path "${each.value.mount}/data/${try(each.value.auth.path, each.key)}${try(each.value.auth.path, each.key) != "" ? "/*" : "*"}" {
  capabilities = ["read", "list"]
}
path "${each.value.mount}/${try(each.value.auth.path, each.key)}${try(each.value.auth.path, each.key) != "" ? "/*" : "*"}" {
  capabilities = ["read", "list"]
}
EOT
}

resource "vault_kubernetes_auth_backend_role" "reader" {
  for_each = local.secret_definitions

  backend                          = "kubernetes"
  role_name                        = try(each.value.auth.role_name, each.key)
  bound_service_account_names      = concat([lookup(each.value, "service_account", each.key)], lookup(each.value, "postgres_secret", false) ? ["postgres-cluster"] : [])
  bound_service_account_namespaces = concat([each.value.namespace], lookup(each.value, "postgres_secret", false) ? ["postgres"] : [])
  token_ttl                        = 3600
  token_policies                   = [vault_policy.reader[each.key].name]
  depends_on                       = [vault_auth_backend.kubernetes, vault_kubernetes_auth_backend_config.backend_config]
}

resource "vault_kv_secret_v2" "config" {
  for_each = local.secret_definitions

  mount     = vault_mount.kv_mounts[each.value.mount].path
  name      = try(each.value.path, "${each.key}/config")
  data_json = jsonencode({
    for key, config in each.value.data : key => (
      lookup(config, "value", null) != null
        ? config.value
        : lookup(config, "readFromVars", false)
          ? config.static[lookup(config, "key_name", key)]
          : random_password.generated["${lookup(config, "key_name", "${each.key}-${key}")}"].result
    )
  })
}