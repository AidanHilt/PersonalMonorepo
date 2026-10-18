locals {
  nix_module_name   = basename(get_terragrunt_dir())
  personal_monorepo = get_env("PERSONAL_MONOREPO_LOCATION", "")
}

# If PERSONAL_MONOREPO_LOCATION is set and points at an existing directory,
# build against that local checkout by overriding the `personalMonorepo`
# flake input instead of its pinned/locked ref. Falls back to the locked
# input (unchanged `nix build` invocation) when the env var is unset/empty
# or the directory doesn't exist. The local checkout path is passed as a
# positional arg ($1) rather than interpolated into the script body, and
# any notice goes to stderr -- this script's stdout becomes the generated
# Terraform config file.
generate "terranix" {
  path      = "generated-config.tf.json"
  disable_signature = true
  if_exists = "overwrite"
  contents  = run_cmd("--terragrunt-quiet", "sh", "-c", <<-EOF
    override_dir="$1"
    override_flag=""
    if [ -n "$override_dir" ] && [ -d "$override_dir" ]; then
      override_flag="--override-input personalMonorepo path:$override_dir"
      echo "terragrunt: using local personalMonorepo checkout at $override_dir" >&2
    fi
    nix build $override_flag ../../../nix/terraform/#packages.aarch64-linux.${local.nix_module_name} && cat result && rm result
  EOF
  , "sh", local.personal_monorepo)
}