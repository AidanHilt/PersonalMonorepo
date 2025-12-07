variable "vault_url" {
  type        = string
  description = "The URL for our vault"
}

variable "vault_token" {
  type        = string
  description = "The token to authenticate with Vault"
}

variable "kubeconfig_location" {
  type        = string
  description = "Where the kubeconfig for our cluster is located"
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  type        = string
  description = "The Kubernetes context to run against"
}

variable "auth_secret_name" {
  type        = string
  description = "The name of the secret that stores the service account token used to run kubernetes auth"
  default     = "vault-sa-token"
}

variable "auth_secret_namespace" {
  type        = string
  description = "The namespace of the secret that stores the service account token used to run kubernetes auth"
  default     = "vault"
}

# Probably want to use env vars for these

# TF_VAR_VPN_AUTH
variable "vpn_auth" {
  type        = string
  description = "The authorization string for the VPN"
}

# TF_VAR_VPN_CONFIG
variable "vpn_config" {
  type        = string
  description = "The config string for the VPN"
}

# TF_VAR_JELLYFIN_EMAIL
variable "jellyfin_email" {
  type        = string
  description = "The email to use for jellyfin"
}

# TF_VAR_JELLYFIN_USERNAME
variable "jellyfin_username" {
  type        = string
  description = "The username of the main administrator account for jellyfin"
  default     = "admin"
}

variable "spotify_public" {
  type        = string
  description = "Public key for spotify app, used by your_spotify"
  default     = ""
}

variable "spotify_private" {
  type        = string
  description = "Private key for spotify app, used by your_spotify"
  default     = ""
}