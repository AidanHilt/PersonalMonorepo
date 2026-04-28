{ ... }: {
  variable.vault_url      = { type = "string"; };
  variable.vault_token    = { type = "string"; sensitive = true; };
  variable.seaweedfs_endpoint = { type = "string"; };
  variable.access_key     = { type = "string"; };
  variable.secret_key     = { type = "string"; sensitive = true; };

  terraform.required_providers.seaweedfs = {
    source  = "JonasKop/seaweedfs";
    version = "0.2.0";
  };

  provider.vault = {
    address = "\${var.vault_url}";
    token   = "\${var.vault_token}";
  };

  # TODO For now, this will only be able to be run from a machine that's port forwarding the service
  # in the future, let's try to secure it with mTLS
  provider.seaweedfs = {
    endpoint   = "\${var.seaweedfs_endpoint}";
    insecure   = true;
    access_key = "\${var.access_key}";
    secret_key = "\${var.secret_key}";
  };
}