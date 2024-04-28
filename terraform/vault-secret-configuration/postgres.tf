# Enable the KV v2 secrets engine
resource "vault_mount" "kv-postgres" {
  path        = "postgres"
  type        = "kv-v2"
  options     = { version = "2" }
  description = "Mount for secrets used in the video stack"
}

# Create a KV v2 secret to store the Prowlarr API key
resource "vault_kv_secret_v2" "postgres_config" {
  mount = vault_mount.kv-postgres.path
  name  = "postgres-config"

  data_json = jsonencode(
    {
      adminPasswordKey = random_password.postgres_master_password.result
    }
  )
}