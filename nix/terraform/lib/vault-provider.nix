<<<<<<< HEAD
{ lib, standalone ? true, ... }:
=======
{ lib, ... }:
>>>>>>> 8f1862e69c7a77b1f101f54c6b645841ebfcfc38

{
  variable = {
    auth_secret_name = {
      type        = "string";
      description = "The name of the secret that stores the service account token used to run kubernetes auth";
      default     = "vault-sa-token";
    };

    auth_secret_namespace = {
      type        = "string";
      description = "The namespace of the secret that stores the service account token used to run kubernetes auth";
      default     = "vault";
    };

    vault_url = {
      type        = "string";
      description = "The URL for our vault";
    };

    vault_token = {
      type        = "string";
      description = "The token to authenticate with Vault";
      sensitive   = true;
    };
  };
<<<<<<< HEAD
  data.kubernetes_secret_v1.vault_auth = lib.mkIf standalone {
=======

  data.kubernetes_secret_v1.vault_auth = {
>>>>>>> 8f1862e69c7a77b1f101f54c6b645841ebfcfc38
    metadata = {
      name = "\${var.auth_secret_name}";
      namespace = "\${var.auth_secret_namespace}";
    };
  };

<<<<<<< HEAD
  provider.vault = lib.mkIf standalone {
=======
  provider.vault = {
>>>>>>> 8f1862e69c7a77b1f101f54c6b645841ebfcfc38
    address = "\${var.vault_url}";
    token   = "\${var.vault_token}";
  };

<<<<<<< HEAD
  resource.vault_auth_backend.kubernetes = lib.mkIf standalone {
=======
  resource.vault_auth_backend.kubernetes = {
>>>>>>> 8f1862e69c7a77b1f101f54c6b645841ebfcfc38
    type = "kubernetes";
    path = "kubernetes";
  };

<<<<<<< HEAD
  resource.vault_kubernetes_auth_backend_config.backend_config = lib.mkIf standalone {
=======
  resource.vault_kubernetes_auth_backend_config.backend_config = {
>>>>>>> 8f1862e69c7a77b1f101f54c6b645841ebfcfc38
    backend            = "\${vault_auth_backend.kubernetes.path}";
    kubernetes_host    = "https://kubernetes.default.svc.cluster.local";
    kubernetes_ca_cert = "\${data.kubernetes_secret_v1.vault_auth.data[\"ca.crt\"]}";
    token_reviewer_jwt = "\${data.kubernetes_secret_v1.vault_auth.data[\"token\"]}";
  };
}