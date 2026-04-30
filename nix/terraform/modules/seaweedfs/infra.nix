{ libFunctions, lib, ... }:

let
  master-secret = libFunctions.mkVaultSecret "seaweedfs-config" {
    service_account = "seaweedfs";
    namespace = "seaweedfs";
    mount = "seaweedfs";
    postgres_secret = false;
    data = {
      # accessKey = {
      #   value = "AKIA\${upper(random_id.admin_access_key.hex)}";
      # };
      secretKey = {
        postgresPassword = false;
      };
    };
  };

  static = {
    variable = {
      vault_url = {
        type        = "string";
        description = "The URL for our vault";
      };
      vault_token = {
        type        = "string";
        description = "The token to authenticate with Vault";
        sensitive   = true;
      };
      seaweedfs_endpoint = {
        type        = "string";
        description = "The endpoint for the seaweedfs S3 API";
        default     = "http://localhost:8333";
      };
      access_key = {
        type        = "string";
        description = "The pre-existing access key for seaweedfs with admin privileges";
      };
      secret_key = {
        type        = "string";
        description = "The pre-existing secret key for seaweedfs with admin privileges";
        sensitive   = true;
      };
      kubeconfig_location = {
        type        = "string";
        description = "Where the kubeconfig for our cluster is located";
        default     = "~/.kube/config";
      };
      kubeconfig_context = {
        type        = "string";
        description = "The Kubernetes context to run against";
      };
    };

    terraform.required_providers.seaweedfs = {
      source  = "JonasKop/seaweedfs";
      version = "0.2.0";
    };

    provider.vault = {
      address = "\${var.vault_url}";
      token   = "\${var.vault_token}";
    };

    provider.kubernetes = {
      config_path    = "\${var.kubeconfig_location}";
      config_context = "\${var.kubeconfig_context}";
    };

    provider.seaweedfs = {
      endpoint   = "\${var.seaweedfs_endpoint}";
      insecure   = true;
      access_key = "\${var.access_key}";
      secret_key = "\${var.secret_key}";
    };

    resource.random_id.admin_access_key = {
      byte_length = 10;
    };
  };
in

lib.recursiveUpdate master-secret static
