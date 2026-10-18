#!/bin/bash
# Generates a temp-dir "extra files" root (an ssh host key, and for
# homelab nodes an rke2 config) for consumption by nixos-anywhere
# --extra-files.
#
# Usage (from a run.sh that also declares "# @lib: generate-node-files",
# "# @lib: printing-and-output" and "# @lib: env-checks" -- @lib is NOT
# transitive, so callers must declare all three themselves):
#
#   FILES_FOR_NEW_MACHINE=$(generate_desktop_files) || { print_error "..."; exit 1; }
#   FILES_FOR_NEW_MACHINE=$(generate_homelab_node_files "$CLUSTER_NAME") || { print_error "..."; exit 1; }
#
# Both functions print ONLY the generated temp-dir path to stdout (with
# no trailing newline) on success -- this is deliberate, since callers
# capture it via $(...). All diagnostics are written to stderr so they
# never corrupt the captured path. Because these functions run inside a
# $(...) subshell, they never call `exit` -- callers must check the exit
# status themselves (e.g. with `|| { ...; exit 1; }` under `set -euo
# pipefail`).

# Internal: generates an ed25519 ssh host key under "$1/etc/ssh". Returns
# non-zero (and leaves nothing behind) if ssh-keygen is missing or fails.
#shellcheck disable=SC2329
_generate_host_key_root() {
  local root="$1"

  if ! command -v ssh-keygen >/dev/null 2>&1; then
    print_error "ssh-keygen is required but was not found on PATH" >&2
    return 1
  fi

  if ! mkdir -p "$root/etc/ssh"; then
    print_error "Failed to create $root/etc/ssh" >&2
    return 1
  fi

  if ! ssh-keygen -t ed25519 -C "noname" -f "$root/etc/ssh/ssh_host_ed25519_key" -N "" >/dev/null 2>&1; then
    print_error "Failed to generate ed25519 host key" >&2
    return 1
  fi

  return 0
}

# generate_desktop_files
#
# Creates a temp dir containing a generated ed25519 ssh host key and
# prints its path to stdout (no trailing newline).
#shellcheck disable=SC2329
generate_desktop_files() {
  local root
  root=$(mktemp -d)

  if ! _generate_host_key_root "$root"; then
    rm -rf "$root"
    return 1
  fi

  printf '%s' "$root"
}

# generate_homelab_node_files <cluster-name>
#
# Creates a temp dir containing a generated ed25519 ssh host key and an
# rke2 config decrypted from the personal monorepo's age-encrypted
# secrets, and prints its path to stdout (no trailing newline). Requires
# PERSONAL_MONOREPO_LOCATION to be set and the `age` tool on PATH. The
# age identity file defaults to "$HOME/.ssh/id_ed25519" and can be
# overridden with NODE_FILES_AGE_IDENTITY.
#shellcheck disable=SC2329
generate_homelab_node_files() {
  local cluster_name="$1"
  local age_identity="${NODE_FILES_AGE_IDENTITY:-$HOME/.ssh/id_ed25519}"
  local age_config_file
  local root

  if [[ -z "$cluster_name" ]]; then
    print_error "generate_homelab_node_files requires a non-empty cluster name" >&2
    return 1
  fi

  if [[ -z "${PERSONAL_MONOREPO_LOCATION:-}" ]]; then
    print_error "PERSONAL_MONOREPO_LOCATION must be set: Path to your personal monorepo" >&2
    return 1
  fi

  if ! command -v age >/dev/null 2>&1; then
    print_error "age is required but was not found on PATH" >&2
    return 1
  fi

  age_config_file="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/secrets/rke-config-$cluster_name.age"
  if [[ ! -f "$age_config_file" ]]; then
    print_error "Age-encrypted rke2 config not found: $age_config_file" >&2
    return 1
  fi

  if [[ ! -f "$age_identity" ]]; then
    print_error "Age identity file not found: $age_identity" >&2
    return 1
  fi

  root=$(mktemp -d)

  if ! _generate_host_key_root "$root"; then
    rm -rf "$root"
    return 1
  fi

  if ! mkdir -p "$root/etc/rancher/rke2"; then
    print_error "Failed to create $root/etc/rancher/rke2" >&2
    rm -rf "$root"
    return 1
  fi

  if ! age -i "$age_identity" -d "$age_config_file" >"$root/etc/rancher/rke2/config.yaml"; then
    print_error "Failed to decrypt $age_config_file" >&2
    rm -rf "$root"
    return 1
  fi

  printf '%s' "$root"
}
