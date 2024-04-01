# Enable the Kubernetes authentication method in Vault
resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

# Retrieve the Kubernetes service account token
data "kubernetes_secret" "vault_auth" {
  metadata {
    name = var.auth_secret_name
    namespace = var.auth_secret_namespace
  }
}

# Configure the Kubernetes authentication method in Vault
resource "vault_kubernetes_auth_backend_config" "example" {
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = "https://kubernetes.default.svc.cluster.local"
  kubernetes_ca_cert = data.kubernetes_secret.vault_auth.data["ca.crt"]
  token_reviewer_jwt = data.kubernetes_secret.vault_auth.data["token"]
}