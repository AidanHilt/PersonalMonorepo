terraform {

}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

inputs = {
  jellyfin_email = get_env("EMAIL_ADDR")
  vpn_auth = get_env("VPN_AUTH")
  vpn_config = get_env("VPN_CONFIG")
  vault_url = get_env("VAULT_ADDR")
  vault_token = get_env("VAULT_TOKEN")
  kubeconfig_context = "kind-kind"
  hwr_applicationkey = run_cmd("--terragrunt-quiet", "keepass-retrieve-secret", "--secret-path", "Server/MyScript", "--key-name", "Username")
  hwr_hmac = run_cmd("--terragrunt-quiet", "keepass-retrieve-secret", "--secret-path", "Server/MyScript")
  open_subtitles_username = run_cmd("--terragrunt-quiet", "keepass-retrieve-secret", "--secret-path", "Internet/OpenSubtitles", "--key-name", "Username")
  open_subtitles_password = run_cmd("--terragrunt-quiet", "keepass-retrieve-secret", "--secret-path", "Internet/OpenSubtitles")
}