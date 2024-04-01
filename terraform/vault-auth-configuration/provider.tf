provider "vault" {
  address = var.vault_url
  token   = var.vault_token
}

# Configure the Kubernetes provider
provider "kubernetes" {
  config_path    = var.kubeconfig_location
  config_context = var.kubeconfig_context
}