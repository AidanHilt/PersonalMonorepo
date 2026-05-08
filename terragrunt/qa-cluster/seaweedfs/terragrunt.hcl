terraform {}


include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

inputs = merge(local.environment_vars.inputs, {
  access_key = run_cmd("--terragrunt-quiet", "keepass-retrieve-secret", "--secret-path", "Server/Seaweedfs", "--key-name", "Username")
  secret_key = run_cmd("--terragrunt-quiet", "keepass-retrieve-secret", "--secret-path", "Server/Seaweedfs")
})