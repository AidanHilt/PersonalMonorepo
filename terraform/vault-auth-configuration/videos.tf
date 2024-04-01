resource "vault_policy" "video_stack_reader" {
  name = "video-stack-reader"

  policy = <<EOT
path "secret/data/videos/*" {
  capabilities = ["read", "list"]
}
EOT
}

# Create a Vault role for the vault-reader-videos service account
resource "vault_kubernetes_auth_backend_role" "video_stack_reader" {
  backend                          = "kubernetes"
  role_name                        = "video-stack-reader"
  bound_service_account_names      = ["vault-reader-videos"]
  bound_service_account_namespaces = ["videos"]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.video_stack_reader.name]
}