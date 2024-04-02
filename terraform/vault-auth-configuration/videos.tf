#============================
# Prowlarr Config
#============================

resource "vault_policy" "prowlarr_reader" {
  name = "prowlarr"

  policy = <<EOT
path "videos/data/prowlarr/*" {
  capabilities = ["read", "list"]
}

path "videos/prowlarr/*" {
  capabilities = ["read", "list"]
}
EOT
}

# Create a Vault role for the vault-reader-videos service account
resource "vault_kubernetes_auth_backend_role" "prowlarr_reader" {
  backend                          = "kubernetes"
  role_name                        = "prowlarr"
  bound_service_account_names      = ["prowlarr"]
  bound_service_account_namespaces = ["videos"]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.prowlarr_reader.name]
  depends_on                       = [vault_auth_backend.kubernetes, vault_kubernetes_auth_backend_config.backend_config]
}

#============================
# Sonarr Config
#============================

resource "vault_policy" "sonarr_reader" {
  name = "prowlarr"

  policy = <<EOT
path "videos/data/sonarr/*" {
  capabilities = ["read", "list"]
}

path "videos/sonarr/*" {
  capabilities = ["read", "list"]
}
EOT
}

# Create a Vault role for the vault-reader-videos service account
resource "vault_kubernetes_auth_backend_role" "sonarr_reader" {
  backend                          = "kubernetes"
  role_name                        = "sonarr"
  bound_service_account_names      = ["sonarr"]
  bound_service_account_namespaces = ["videos"]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.sonarr_reader.name]
  depends_on                       = [vault_auth_backend.kubernetes, vault_kubernetes_auth_backend_config.backend_config]
}