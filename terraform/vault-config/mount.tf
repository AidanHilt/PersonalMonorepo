resource "vault_mount" "kv_mounts" {
  for_each = local.unique_mounts

  path        = each.value
  type        = "kv-v2"
  description = "KV v2 secrets mount for ${each.value}"

  options = {
    version = "2"
  }
}