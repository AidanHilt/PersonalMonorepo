# Enable the KV v2 secrets engine
resource "vault_mount" "kv-videos" {
  path        = "videos"
  type        = "kv-v2"
  options     = { version = "2" }
  description = "Mount for secrets used in the video stack"
}

# Create a KV v2 secret to store the Prowlarr API key
resource "vault_kv_secret_v2" "prowlarr_config" {
  mount = vault_mount.kv-videos.path
  name  = "prowlarr/config"

  data_json = jsonencode(
    {
      apiKey           = random_password.prowlarr_api_key.result
      postgresUsername = var.postgres_prowlarr_username
      postgresPassword = random_password.postgres_prowlarr_password.result
    }
  )
}

resource "vault_kv_secret_v2" "sonarr_api_key" {
  mount = vault_mount.kv-videos.path
  name  = "sonarr/api-key"

  data_json = jsonencode(
    {
      apiKey           = random_password.prowlarr_api_key.result
      postgresUsername = var.postgres_prowlarr_username
      postgresPassword = random_password.postgres_prowlarr_password.result
    }
  )
}

resource "vault_kv_secret_v2" "radarr_api_key" {
  mount = vault_mount.kv-videos.path
  name  = "radarr/api-key"

  data_json = jsonencode(
    {
      apiKey = random_password.radarr_api_key.result
    }
  )
}