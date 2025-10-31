locals {
  secret_definitions = [
    {
      name      = "prowlarr"
      namespace = "videos"
      mount     = "videos"
      data      = {
        apiKey           = random_password.prowlarr_api_key.result
        postgresUsername = var.postgres_prowlarr_username
        postgresPassword = random_password.postgres_prowlarr_password.result
      }
    }
  ]
}

resource "vault_policy" "reader" {
  for_each = { for secret in local.secret_definitions : secret.name => secret }

  name = each.value.name
  policy = <<EOT
path "${each.value.mount}/data/${each.value.name}/*" {
  capabilities = ["read", "list"]
}
path "${each.value.mount}/${each.value.name}/*" {
  capabilities = ["read", "list"]
}
EOT
}

resource "vault_kubernetes_auth_backend_role" "reader" {
  for_each = { for secret in local.secret_definitions : secret.name => secret }

  backend                          = "kubernetes"
  role_name                        = each.value.name
  bound_service_account_names      = [each.value.name]
  bound_service_account_namespaces = [each.value.namespace]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.reader[each.key].name]
  depends_on                       = [vault_auth_backend.kubernetes, vault_kubernetes_auth_backend_config.backend_config]
}

resource "vault_kv_secret_v2" "config" {
  for_each = { for secret in local.secret_definitions : secret.name => secret }

  mount     = vault_mount.kv[each.value.mount].path
  name      = "${each.value.name}/config"
  data_json = jsonencode(each.value.data)
}