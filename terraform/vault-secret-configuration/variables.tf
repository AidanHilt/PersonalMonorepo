variable "vault_url" {
  type        = string
  description = "The URL for our vault"
}

variable "vault_token" {
  type        = string
  description = "The token to authenticate with Vault"
}

variable "postgres_prowlarr_username" {
  type        = string
  description = "The username for the prowlarr user"
  default     = "prowlarr_user"
}

variable "postgres_sonarr_username" {
  type        = string
  description = "The username for the sonarr user"
  default     = "radarr_user"
}

variable "postgres_radarr_username" {
  type        = string
  description = "The username for the radarr user"
  default     = "radarr_user"
}

variable "postgres_master_username" {
  type        = string
  description = "The username for the postgres master user"
  default     = "postgres"
}

variable "jellyfin_username" {
  type        = string
  description = "The username for a default admin user on Jellyfin"
  default     = "admin"
}