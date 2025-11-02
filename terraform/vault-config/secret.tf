resource "vault_policy" "reader" {
  for_each = { for secret in local.secret_definitions : secret.name => secret }

  name = try(each.value.auth.role_name, each.value.name)

  policy = <<EOT
path "${each.value.mount}/data/${try(each.value.auth.path, each.value.name)}${try(each.value.auth.path, each.value.name) != "" ? "/*" : "*"}" {
  capabilities = ["read", "list"]
}
path "${each.value.mount}/${try(each.value.auth.path, each.value.name)}${try(each.value.auth.path, each.value.name) != "" ? "/*" : "*"}" {
  capabilities = ["read", "list"]
}
EOT
}

resource "vault_kubernetes_auth_backend_role" "reader" {
  for_each = { for secret in local.secret_definitions : secret.name => secret }

  backend                          = "kubernetes"
  role_name                        = try(each.value.auth.role_name, each.value.name)
  bound_service_account_names      = concat([lookup(each.value, "service_account", each.value.name)], lookup(each.value, "postgres_secret", false) ? ["postgres-cluster"] : [])
  bound_service_account_namespaces = concat([each.value.namespace], lookup(each.value, "postgres_secret", false) ? ["postgres"] : [])
  token_ttl                        = 3600
  token_policies                   = [vault_policy.reader[each.key].name]
  depends_on                       = [vault_auth_backend.kubernetes, vault_kubernetes_auth_backend_config.backend_config]
}

resource "vault_kv_secret_v2" "config" {
  for_each = { for secret in local.secret_definitions : secret.name => secret }

  mount     = vault_mount.kv_mounts[each.value.mount].path
  name      = try(each.value.path, "${each.value.name}/config")
  data_json = jsonencode({
    for key, config in each.value.data : key => (
      lookup(config, "value", null) != null
        ? config.value
        : lookup(config, "readFromVars", false)
          ? config.static[lookup(config, "key_name", key)]
          : random_password.generated["${lookup(config, "key_name", "${each.value.name}-${key}")}"].result
    )
  })
}