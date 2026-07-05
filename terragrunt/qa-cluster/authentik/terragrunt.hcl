terraform {

}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

inputs = {
  vault_url = get_env("VAULT_ADDR")
  vault_token = get_env("VAULT_TOKEN")
  kubeconfig_context = "kind-kind"
  authentik_access_url = "http://iam.qa-cluster-lb.lan"
  authentik_token = ""
  authentik_insecure = true
  secure = false
  basename(dirname(get_terragrunt_dir())) = true
}