resource "vault_policy" "video_stack_reader" {
  name = "prowlarr"

  policy = <<EOT
path "videos/prowlarr" {
  capabilities = ["read", "list"]
}
EOT
}

# Create a Vault role for the vault-reader-videos service account
resource "vault_kubernetes_auth_backend_role" "video_stack_reader" {
  backend                          = "kubernetes"
  role_name                        = "prowlarr"
  bound_service_account_names      = ["prowlarr"]
  bound_service_account_namespaces = ["videos"]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.video_stack_reader.name]
  depends_on                       = [vault_auth_backend.kubernetes, vault_kubernetes_auth_backend_config.backend_config]
}