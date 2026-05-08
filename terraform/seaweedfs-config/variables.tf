variable "vault_url" {
  type        = string
  description = "The URL for our vault"
}

variable "vault_token" {
  type        = string
  description = "The token to authenticate with Vault"
}

variable "seaweedfs_endpoint" {
  type        = string
  description = "The endpoint for the seaweedfs S3 API"
  default     = "http://localhost:8333"
}

variable "access_key" {
  type        = string
  description = "The pre-existing access key for seaweedfs with admin privileges"
}

variable "secret_key" {
  type        = string
  description = "The pre-existing secret key for seaweedfs with admin privileges"
}