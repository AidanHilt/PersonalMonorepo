terraform {
  source = "../../../terraform/vault-config"
}

inputs = {
  jellyfin_email = get_env("EMAIL_ADDR")
  vpn_auth = get_env("VPN_AUTH")
  vpn_config = get_env("VPN_CONFIG")
  vault_url = get_env("VAULT_ADDR")
  vault_token = get_env("VAULT_TOKEN")
  kubeconfig_context = "prod-cluster"

  spotify_public = run_cmd("keepass-retrieve-secret", "--secret-path", "Server/Your_Spotify", "--key-name", "Username")
  spotify_private = run_cmd("keepass-retrieve-secret", "--secret-path", "Server/Your_Spotify")
}