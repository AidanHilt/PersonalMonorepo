inputs = {
  vault_url = get_env("VAULT_ADDR")
  vault_token = get_env("VAULT_TOKEN")
  kubeconfig_context = "prod-cluster"
}