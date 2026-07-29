{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

system-tasks-add-trust-certs = pkgs.writeShellScriptBin "system-tasks-add-trust-certs" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

GITHUB_OWNER="AidanHilt"
GITHUB_REPO="PersonalMonorepo"
CONFIG_ROOT_PATH="kubernetes/argocd/configuration-data"
GITHUB_API_URL="https://api.github.com/repos/''${GITHUB_OWNER}/''${GITHUB_REPO}/contents/''${CONFIG_ROOT_PATH}"
RAW_BASE_URL="https://raw.githubusercontent.com/''${GITHUB_OWNER}/''${GITHUB_REPO}/master/''${CONFIG_ROOT_PATH}"
DEFAULT_OUT_DIR="''${HOME}/.local/share/vault-ca"

require_env() {
  if [[ -z "''${VAULT_ADDR:-}" || -z "''${VAULT_TOKEN:-}" ]]; then
    print_error "VAULT_ADDR and VAULT_TOKEN must both be set in the environment. Use context-activate-context to enable the proper env, if needed."
    exit 1
  fi
}

list_clusters() {
  curl -sf "''${GITHUB_API_URL}" | jq -r '.[] | select(.type == "dir") | .name'
}

select_cluster() {
  local clusters=("$@")
  local index
  local chosen

  index=1
  echo "$clusters"
  for cluster_name in "''${clusters[@]}"; do
    echo "''${index}) ''${cluster_name}" >&2
    index=$((index + 1))
  done

  chosen=""
  while [[ -z "''${chosen}" ]]; do
    read -rp "Select a cluster: " chosen

    if [[ ! "''${chosen}" =~ ^[0-9]+$ ]] || (( chosen < 1 || chosen > ''${#clusters[@]} )); then
      print_warning "Invalid selection, try again."
      chosen=""
    fi
  done

  echo "''${clusters[$((chosen - 1))]}"
}


fetch_hostnames() {
  local cluster="$1"
  local STACK_URL="''${RAW_BASE_URL}/''${cluster}/master-stack.yaml"

  curl -sf "''${STACK_URL}" | yq -r '.hostnames[]'
}

safe_hostname() {
  local hostname="$1"

  echo "''${hostname//./-}"
}

fetch_cert() {
  local PKI_MOUNT="$1"
  local OUT_DIR="$2"
  local CERT_FILE="''${OUT_DIR}/''${PKI_MOUNT}.pem"

  print_debug "Fetching intermediate CA cert from Vault mount: ''${PKI_MOUNT}"
  mkdir -p "''${OUT_DIR}"
  vault read -field=certificate "''${PKI_MOUNT}/cert/ca" > "''${CERT_FILE}"

  if [[ ! -s "''${CERT_FILE}" ]]; then
    print_error "Fetched cert is empty for mount: ''${PKI_MOUNT}"
    exit 1
  fi

  echo "''${CERT_FILE}"
}

install_nss() {
  local CERT_FILE="$1"
  local CERT_NAME="$2"
  local profile_dirs=()

  mapfile -t profile_dirs < <(find "''${HOME}/.mozilla/firefox" "''${HOME}/Library/Application Support/Firefox/Profiles" -maxdepth 1 -type d -name '*.default*' 2>/dev/null)

  if [[ -d "''${HOME}/.pki/nssdb" ]]; then
    profile_dirs+=("''${HOME}/.pki/nssdb")
  fi

  if [[ ''${#profile_dirs[@]} -eq 0 ]]; then
    print_warning "No Firefox/Chrome NSS profiles found for ''${CERT_NAME}."
    return
  fi

  local profile_dir
  for profile_dir in "''${profile_dirs[@]}"; do
    print_debug "Trusting ''${CERT_NAME} in NSS DB: ''${profile_dir}"
    certutil -A -n "''${CERT_NAME}" -t "CT,C,C" -i "''${CERT_FILE}" -d "sql:''${profile_dir}"
  done
}

install_macos_keychain() {
  local CERT_FILE="$1"

  print_debug "Adding ''${CERT_FILE} to macOS login keychain"
  security add-trusted-cert -d -r trustAsRoot -k "''${HOME}/Library/Keychains/login.keychain-db" "''${CERT_FILE}"
}

print_nixos_instructions() {
  local CERT_FILE="$1"

  print_debug "NixOS system-wide trust: add \"''${CERT_FILE}\" to security.pki.certificateFiles in configuration.nix, then run 'sudo nixos-rebuild switch'"
  print_debug "For shell-only trust: export NIX_SSL_CERT_FILE=\"''${CERT_FILE}\" and SSL_CERT_FILE=\"''${CERT_FILE}\""
}

trust_hostname() {
  local hostname="$1"
  local out_dir="$2"
  local SAFE_NAME
  SAFE_NAME="$(safe_hostname "''${hostname}")"
  local PKI_MOUNT="pki_int_''${SAFE_NAME}"
  local CERT_NAME="Vault Intermediate CA - ''${hostname}"
  local CERT_FILE
  CERT_FILE="$(fetch_cert "''${PKI_MOUNT}" "''${out_dir}")"

  case "$(uname -s)" in
    Darwin)
      install_macos_keychain "''${CERT_FILE}"
      ;;
    Linux)
      print_nixos_instructions "''${CERT_FILE}"
      ;;
    *)
      print_warning "Unrecognized OS, cert saved to ''${CERT_FILE}"
      ;;
  esac
}

parse_args() {
  cluster=""
  out_dir="''${DEFAULT_OUT_DIR}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cluster)
        cluster="$2"
        shift 2
        ;;
      --out-dir)
        out_dir="$2"
        shift 2
        ;;
      *)
        print_error "Unknown argument: $1"
        exit 1
        ;;
    esac
  done
}

main() {
  require_env
  parse_args "$@"


  if [[ -z "''${cluster}" ]]; then
    local CLUSTERS
    mapfile -t CLUSTERS < <(list_clusters)
    cluster="$(select_cluster "''${CLUSTERS[@]}")"
  fi

  local HOSTNAMES
  mapfile -t HOSTNAMES < <(fetch_hostnames "''${cluster}")

  local hostname
  for hostname in "''${HOSTNAMES[@]}"; do
    trust_hostname "''${hostname}" "''${out_dir}"
  done

  print_status "Finished trusting intermediate CA certs for cluster: ''${cluster}. Restart your browser for changes to take effect."
}

main "$@"
'';
in

{
  environment.systemPackages = [
    system-tasks-add-trust-certs
  ];
}