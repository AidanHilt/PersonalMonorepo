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
  name   = "sonarr"

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
  name   = "radarr"

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

#============================
# Setup Job Config
#============================

resource "vault_policy" "setup_job_reader" {
  name   = "setup_job"

  policy = <<EOT
path "videos/data/setup_job/*" {
  capabilities = ["read", "list"]
}

path "videos/setup_job/*" {
  capabilities = ["read", "list"]
}
EOT
}

resource "vault_kubernetes_auth_backend_role" "setup_job_reader" {
  backend                          = "kubernetes"
  role_name                        = "setup_job"
  bound_service_account_names      = ["setup-job"]
  bound_service_account_namespaces = ["videos"]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.setup_job_reader.name]
  depends_on                       = [vault_auth_backend.kubernetes, vault_kubernetes_auth_backend_config.backend_config]
}

#============================
# Jellyfin Config
#============================

resource "vault_policy" "jellyfin_reader" {
  name   = "jellyfin"

  policy = <<EOT
path "videos/data/jellyfin/*" {
  capabilities = ["read", "list"]
}

path "videos/jellyfin/*" {
  capabilities = ["read", "list"]
}
EOT
}

resource "vault_kubernetes_auth_backend_role" "jellyfin_reader" {
  backend                          = "kubernetes"
  role_name                        = "jellyfin"
  bound_service_account_names      = ["jellyfin"]
  bound_service_account_namespaces = ["videos"]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.jellyfin_reader.name]
  depends_on                       = [vault_auth_backend.kubernetes, vault_kubernetes_auth_backend_config.backend_config]
}


#============================
# Jellyseerr Config
#============================

resource "vault_policy" "jellyseerr_reader" {
  name   = "jellyseerr"

  policy = <<EOT
path "videos/data/jellyseerr/*" {
  capabilities = ["read", "list"]
}

path "videos/jellyseerr/*" {
  capabilities = ["read", "list"]
}
EOT
}

resource "vault_kubernetes_auth_backend_role" "jellyseerr_reader" {
  backend                          = "kubernetes"
  role_name                        = "jellyseerr"
  bound_service_account_names      = ["jellyseerr"]
  bound_service_account_namespaces = ["videos"]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.jellyseerr_reader.name]
  depends_on                       = [vault_auth_backend.kubernetes, vault_kubernetes_auth_backend_config.backend_config]
}