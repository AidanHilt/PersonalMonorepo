# Enable the KV v2 secrets engine
resource "vault_mount" "kv-argocd" {
  path        = "argocd"
  type        = "kv-v2"
  options     = { version = "2" }
  description = "Mount for secrets used directly in ArgoCD that can't or won't pull from secrets"
}

resource "vault_kv_secret_v2" "video_stack_configuration" {
  mount = vault_mount.kv-argocd.path
  name  = "video_stack_configuration"

  data_json = jsonencode(
    {
      prowlarrApiKey   = random_password.prowlarr_api_key.result
      sonarrApiKey     = random_password.sonarr_api_key.result
      radarrApiKey     = random_password.radarr_api_key.result
      jellyseerrApiKey = random_password.jellyseerr_api_key.result
      jellyfinUsername = var.jellyfin_username
      jellyfinPassword = random_password.jellyfin_password.result
      jellyfinEmail    = var.jellyfin_email
    }
  )
}