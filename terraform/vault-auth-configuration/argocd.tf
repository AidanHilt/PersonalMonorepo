resource "vault_policy" "argocd_reader" {
  name = "argocd"

  policy = <<EOT
path "argocd/data/*" {
  capabilities = ["read", "list"]
}

path "argocd/*" {
  capabilities = ["read", "list"]
}
EOT
}

resource "vault_kubernetes_auth_backend_role" "argocd_reader" {
  backend                          = "kubernetes"
  role_name                        = "argocd"
  bound_service_account_names      = ["argocd"]
  bound_service_account_namespaces = ["argocd"]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.argocd_reader.name]
  depends_on                       = [vault_auth_backend.kubernetes, vault_kubernetes_auth_backend_config.backend_config]
}