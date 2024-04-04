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
  description = "Where the kubeconfig for our cluster is located. This is assumed to be running locally"
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