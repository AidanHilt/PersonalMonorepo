terraform {
  required_providers {
    seaweedfs = {
      source = "JonasKop/seaweedfs"
      version = "0.2.0"
    }
  }
}

provider "vault" {
  address = var.vault_url
  token   = var.vault_token
}

<<<<<<< HEAD
provider "seaweedfs" {
  # TODO For now, this will only be able to be run from a machine that's port forwarding the service
  # in the future, let's try to secure it with mTLS
  endp = var.seaweedfs_endpoint
  insecure = true

  access_key = var.access_key
  secret_key = var.secret_key
}
=======
>>>>>>> 8f1862e69c7a77b1f101f54c6b645841ebfcfc38
