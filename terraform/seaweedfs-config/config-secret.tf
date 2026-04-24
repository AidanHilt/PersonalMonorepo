locals {
  s3_config = jsonencode({
    identities = [
      {
        name = "admin"
        credentials = [
          {
            accessKey = "AKIA${upper(random_id.admin_access_key.hex)}"
            secretKey = random_password.admin_secret_key.result
          }
        ]
        actions = ["Admin", "Read", "Write", "List", "Tagging"]
      }
    ]
  })
}

resource "vault_kv_secret_v2" "seaweedfs_s3_config" {
  mount = "seaweedfs"
  name  = "admin-config"

  data_json = jsonencode({
    seaweedfs_s3_config = local.s3_config
    access_key          = "AKIA${upper(random_id.admin_access_key.hex)}"
    secret_key          = random_password.admin_secret_key.result
  })
}

resource "vault_policy" "seaweedfs_s3_read" {
  name = "seaweedfs-s3-config-read"

  policy = <<-EOT
    path "seaweedfs/data/admin-config" {
      capabilities = ["read"]
    }
    path "seaweedfs/admin-config" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "seaweedfs" {
  backend                          = "kubernetes"
  role_name                        = "seaweedfs-s3-config"
  bound_service_account_names      = ["seaweedfs"]
  bound_service_account_namespaces = ["seaweedfs"]
  token_policies                   = [vault_policy.seaweedfs_s3_read.name]
  token_ttl                        = 3600
}
