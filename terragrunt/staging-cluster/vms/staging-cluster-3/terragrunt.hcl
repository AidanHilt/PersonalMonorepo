locals {
  vm_vars = read_terragrunt_config(find_in_parent_folders("vms.hcl"))
}

terraform {
  source = "../../../../terraform/staging-cluster-vm"
}

inputs = merge(local.vm_vars.inputs, {
  vm_name = "staging-cluster-3"
  mac_address = "AE:C5:F8:BB:4E:AB" 
})