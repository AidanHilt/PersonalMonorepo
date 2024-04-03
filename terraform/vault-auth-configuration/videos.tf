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
  name = "sonarr"

  policy = <<EOT
path "videos/data/sonarr/*" {
  capabilities = ["read", "list"]
}

path "videos/sonarr/*" {
  capabilities = ["read", "list"]
}
EOT
}

resource "vault_kubernetes_auth_backend_role" "sonarr_reader" {
  backend                          = "kubernetes"
  role_name                        = "sonarr"
  bound_service_account_names      = ["sonarr"]
  bound_service_account_namespaces = ["videos"]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.sonarr_reader.name]
  depends_on                       = [vault_auth_backend.kubernetes, vault_kubernetes_auth_backend_config.backend_config]
}

#============================
# Radarr Config
#============================

resource "vault_policy" "radarr_reader" {
  name = "radarr"

  policy = <<EOT
path "videos/data/radarr/*" {
  capabilities = ["read", "list"]
}

path "videos/radarr/*" {
  capabilities = ["read", "list"]
}
EOT
}

resource "vault_kubernetes_auth_backend_role" "radarr_reader" {
  backend                          = "kubernetes"
  role_name                        = "radarr"
  bound_service_account_names      = ["radarr"]
  bound_service_account_namespaces = ["videos"]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.radarr_reader.name]
  depends_on                       = [vault_auth_backend.kubernetes, vault_kubernetes_auth_backend_config.backend_config]
}