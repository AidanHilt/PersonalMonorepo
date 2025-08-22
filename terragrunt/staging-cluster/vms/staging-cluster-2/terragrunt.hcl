locals {
  vm_vars = read_terragrunt_config(find_in_parent_folders("vms.hcl"))
}

terraform {
  source = "../../../../terraform/staging-cluster-vm"
}

inputs = merge(local.vm_vars.inputs, {
  vm_name = "staging-cluster-2"
  mac_address = "86:E3:77:01:D8:06" 
})