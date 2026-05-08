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

