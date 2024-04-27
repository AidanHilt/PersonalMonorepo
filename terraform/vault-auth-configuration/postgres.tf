resource "vault_policy" "postgres_reader" {
  name   = "postgres"

  policy = <<EOT
path "postgres/*" {
  capabilities = ["read", "list"]
}

path "postgres/*" {
  capabilities = ["read", "list"]
}
EOT
}

resource "vault_kubernetes_auth_backend_role" "postgres_reader" {
  backend                          = "kubernetes"
  role_name                        = "postgres"
  bound_service_account_names      = ["postgres-postgresql"]
  bound_service_account_namespaces = ["postgres"]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.postgres_reader.name]
  depends_on                       = [vault_auth_backend.kubernetes, vault_kubernetes_auth_backend_config.backend_config]
}