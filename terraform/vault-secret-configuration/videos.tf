provider "vault" {
  address = var.vault_url
  token   = var.vault_token
}

# Enable the KV v2 secrets engine
resource "vault_mount" "kv" {
  path        = "videos"
  type        = "kv"
  options     = { version = "2" }
  description = "Mount for secrets used in the video stack"
}

# Generate a random password for the Prowlarr API key
resource "random_password" "prowlarr_api_key" {
  length  = 32
  special = false
  upper   = false
}

resource "random_password" "sonarr_api_key" {
  length  = 32
  special = false
  upper   = false
}

resource "random_password" "radarr_api_key" {
  length  = 32
  special = false
  upper   = false
}

# Create a KV v2 secret to store the Prowlarr API key
resource "vault_kv_secret_v2" "prowlarr_api_key" {
  mount = vault_mount.kv.path
  name  = "prowlarr/api-key"

  data_json = jsonencode(
    {
      apiKey = random_password.prowlarr_api_key.result
    }
  )
}

resource "vault_kv_secret_v2" "sonarr_api_key" {
  mount = vault_mount.kv.path
  name  = "sonarr/api-key"

  data_json = jsonencode(
    {
      apiKey = random_password.prowlarr_api_key.result
    }
  )
}

resource "vault_kv_secret_v2" "radarr_api_key" {
  mount = vault_mount.kv.path
  name  = "radarr/api-key"

  data_json = jsonencode(
    {
      apiKey = random_password.prowlarr_api_key.result
    }
  )
}