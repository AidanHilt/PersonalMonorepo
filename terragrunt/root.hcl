locals {
  nix_module_name = basename(get_terragrunt_dir())
}

generate "terranix" {
  path      = "generated-config.tf.json"
  disable_signature = true
  if_exists = "overwrite"
  contents  = run_cmd("--terragrunt-quiet", "sh", "-c", "nix build ../../../nix/terraform/#packages.aarch64-linux.${local.nix_module_name} && cat result && rm result")
}