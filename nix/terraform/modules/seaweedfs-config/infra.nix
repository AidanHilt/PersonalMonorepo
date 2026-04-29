{ ... }:

{
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
  };

  terraform.required_providers.seaweedfs = {
    source  = "JonasKop/seaweedfs";
    version = "0.2.0";
  };

  provider.vault = {
    address = "\${var.vault_url}";
    token   = "\${var.vault_token}";
  };

  provider.seaweedfs = {
    endpoint   = "\${var.seaweedfs_endpoint}";
    insecure   = true;
    access_key = "\${var.access_key}";
    secret_key = "\${var.secret_key}";
  };
}