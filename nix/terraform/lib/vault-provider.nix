{ lib, ... }:

{
  data.kubernetes_secret_v1.vault_auth = {
    metadata = {
      name = "\${var.auth_secret_name}";
      namespace = "\${var.auth_secret_namespace}";
    };
  };

  resource.vault_auth_backend.kubernetes = {
    type = "kubernetes";
    path = "kubernetes";
  };

  resource.vault_kubernetes_auth_backend_config.backend_config = {
    backend            = "\${vault_auth_backend.kubernetes.path}";
    kubernetes_host    = "https://kubernetes.default.svc.cluster.local";
    kubernetes_ca_cert = "\${data.kubernetes_secret_v1.vault_auth.data[\"ca.crt\"]}";
    token_reviewer_jwt = "\${data.kubernetes_secret_v1.vault_auth.data[\"token\"]}";
  };

  variable.auth_secret_name = {
    type        = "string";
    description = "The name of the secret that stores the service account token used to run kubernetes auth";
    default     = "vault-sa-token";
  };

  variable.auth_secret_namespace = {
    type        = "string";
    description = "The namespace of the secret that stores the service account token used to run kubernetes auth";
    default     = "vault";
  };
}