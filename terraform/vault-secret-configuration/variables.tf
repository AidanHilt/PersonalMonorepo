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