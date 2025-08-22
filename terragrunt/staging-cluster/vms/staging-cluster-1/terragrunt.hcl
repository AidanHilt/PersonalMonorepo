locals {
  vm_vars = read_terragrunt_config(find_in_parent_folders("vms.hcl"))
}

terraform {
  source = "../../../../terraform/staging-cluster-vm"
}

inputs = merge(local.vm_vars.inputs, {
  vm_name = "staging-cluster-1"
  mac_address = "A0:C5:5D:CA:EA:6D" 
})