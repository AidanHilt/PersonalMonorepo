locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "../../../../terraform/vault-auth-configuration"
}

inputs = merge(local.environment_vars.inputs, {
  kubeconfig_context = "new-prod-cluster"
})