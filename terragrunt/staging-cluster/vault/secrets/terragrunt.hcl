locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "../../../../terraform/vault-secret-configuration"
}

inputs = merge(local.environment_vars.inputs, {
  jellyfin_email = get_env("EMAIL_ADDR")
})