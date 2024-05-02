# Enable the KV v2 secrets engine
resource "vault_mount" "kv-videos" {
  path        = "videos"
  type        = "kv-v2"
  options     = { version = "2" }
  description = "Mount for secrets used in the video stack"
}


#===============
# Prowlarr
#===============
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

#===============
# Sonarr
#===============
resource "vault_kv_secret_v2" "sonarr_config" {
  mount = vault_mount.kv-videos.path
  name  = "sonarr/config"

  data_json = jsonencode(
    {
      apiKey           = random_password.prowlarr_api_key.result
      postgresUsername = var.postgres_sonarr_username
      postgresPassword = random_password.postgres_sonarr_password.result
    }
  )
}

#===============
# Radarr
#===============
resource "vault_kv_secret_v2" "radarr_config" {
  mount = vault_mount.kv-videos.path
  name  = "radarr/config"

  data_json = jsonencode(
    {
      apiKey           = random_password.prowlarr_api_key.result
      postgresUsername = var.postgres_radarr_username
      postgresPassword = random_password.postgres_radarr_password.result
    }
  )
}

#===============
# Setup Job
#===============
resource "vault_kv_secret_v2" "setup_job_config" {
  mount = vault_mount.kv-videos.path
  name  = "setup_job/config"

  data_json = jsonencode(
    {
      masterUsername = var.postgres_master_username
      masterPassword = random_password.postgres_master_password.result
    }
  )
}