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

resource "random_password" "jellyfin_api_key" {
  length  = 32
  special = false
  upper   = false
}

resource "random_password" "jellyseerr_api_key" {
  length  = 64
  special = false
  upper   = false
}

resource "random_password" "postgres_master_password" {
  length = 64
}

resource "random_password" "postgres_prowlarr_password" {
  length = 64
  override_special = "!#$%*()-_=+[]{}:?"
}

resource "random_password" "postgres_sonarr_password" {
  length = 64
  override_special = "!#$%*()-_=+[]{}:?"
}

resource "random_password" "postgres_radarr_password" {
  length = 64
  override_special = "!#$%*()-_=+[]{}:?"
}

resource "random_password" "postgres_jellyseerr_password" {
  length = 64
  override_special = "!#$%*()-_=+[]{}?"
}

resource "random_password" "jellyfin_password" {
  length = 64
  override_special = "!#$%*()-_=+[]{}?"
}