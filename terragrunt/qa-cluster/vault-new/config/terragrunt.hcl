locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "../../../../terraform/vault-config"
}

inputs = merge(local.environment_vars.inputs, {
  jellyfin_email = get_env("EMAIL_ADDR")
  vpn_auth = get_env("VPN_AUTH")
  vpn_config = get_env("VPN_CONFIG")
})