locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "../../../../terraform/grafana-dashboard-deployment"
}

inputs = merge(local.environment_vars.inputs, {})