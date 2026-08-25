#!/bin/bash

set -euo pipefail

# @lib: printing-and-output

GITHUB_OWNER="AidanHilt"
GITHUB_REPO="PersonalMonorepo"
CONFIG_ROOT_PATH="kubernetes/argocd/configuration-data"
GITHUB_API_URL="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/${CONFIG_ROOT_PATH}"
RAW_BASE_URL="https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/master/${CONFIG_ROOT_PATH}"
DEFAULT_OUT_DIR="${HOME}/.local/share/vault-ca"

require_env() {
  if [[ -z "${VAULT_ADDR:-}" || -z "${VAULT_TOKEN:-}" ]]; then
    print_error "VAULT_ADDR and VAULT_TOKEN must both be set in the environment. Use context-activate-context to enable the proper env, if needed."
    exit 1
  fi
}

list_clusters() {
  curl -sf "${GITHUB_API_URL}" | jq -r '.[] | select(.type == "dir") | .name'
}

select_cluster() {
  local clusters=("$@")
  local index
  local chosen

  index=1
  for cluster_name in "${clusters[@]}"; do
    echo "${index}) ${cluster_name}" >&2
    index=$((index + 1))
  done

  chosen=""
  while [[ -z "${chosen}" ]]; do
    read -rp "Select a cluster: " chosen

    if [[ ! "${chosen}" =~ ^[0-9]+$ ]] || ((chosen < 1 || chosen > ${#clusters[@]})); then
      print_warning "Invalid selection, try again."
      chosen=""
    fi
  done

  echo "${clusters[$((chosen - 1))]}"
}

fetch_hostnames() {
  local cluster="$1"
  local STACK_URL="${RAW_BASE_URL}/${cluster}/master-stack.yaml"

  curl -s "${STACK_URL}" | yq -r '.hostnames[]'
}

safe_hostname() {
  local hostname="$1"

  echo "${hostname//./-}"
}

fetch_cert() {
  local PKI_MOUNT="$1"
  local OUT_DIR="$2"
  local CERT_FILE="${OUT_DIR}/${PKI_MOUNT}.pem"

  print_debug "Fetching intermediate CA cert from Vault mount: ${PKI_MOUNT}"
  mkdir -p "${OUT_DIR}"
  vault read -field=certificate "${PKI_MOUNT}/cert/ca" >"${CERT_FILE}"

  if [[ ! -s "${CERT_FILE}" ]]; then
    print_error "Fetched cert is empty for mount: ${PKI_MOUNT}"
    exit 1
  fi

  echo "${CERT_FILE}"
}

install_macos_keychain() {
  local CERT_FILE="$1"
  local KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

  local CERT_CN
  CERT_CN=$(openssl x509 -noout -subject -in "${CERT_FILE}" | sed -n 's/.*CN\s*=\s*\([^,/]*\).*/\1/p')

  if [[ -z "${CERT_CN}" ]]; then
    print_debug "Could not determine CN for ${CERT_FILE}, skipping duplicate check"
  else
    local NEW_FINGERPRINT
    NEW_FINGERPRINT=$(openssl x509 -noout -fingerprint -sha1 -in "${CERT_FILE}" | sed 's/^.*=//; s/://g')

    # find-certificate only returns the first match, so loop until none are left
    while security find-certificate -c "${CERT_CN}" -Z "${KEYCHAIN}" >/dev/null 2>&1; do
      local EXISTING_FINGERPRINT
      EXISTING_FINGERPRINT=$(security find-certificate -c "${CERT_CN}" -Z "${KEYCHAIN}" |
        sed -n 's/^SHA-1 hash: //p')

      if [[ "${EXISTING_FINGERPRINT}" == "${NEW_FINGERPRINT}" ]]; then
        print_debug "Identical cert for ${CERT_CN} already trusted in keychain, skipping"
        return 0
      fi

      print_debug "Removing stale cert for ${CERT_CN} (${EXISTING_FINGERPRINT}) from keychain"
      security delete-certificate -Z "${EXISTING_FINGERPRINT}" "${KEYCHAIN}"
    done
  fi

  print_debug "Adding ${CERT_FILE} to macOS login keychain"
  security add-trusted-cert -d -r trustAsRoot -k "${KEYCHAIN}" "${CERT_FILE}"
}

print_nixos_instructions() {
  local CERT_FILE="$1"

  print_debug "NixOS system-wide trust: add \"${CERT_FILE}\" to security.pki.certificateFiles in configuration.nix, then run 'sudo nixos-rebuild switch'"
  print_debug "For shell-only trust: export NIX_SSL_CERT_FILE=\"${CERT_FILE}\" and SSL_CERT_FILE=\"${CERT_FILE}\""
}

trust_hostname() {
  local hostname="$1"
  local out_dir="$2"
  local SAFE_NAME
  SAFE_NAME="$(safe_hostname "${hostname}")"
  local PKI_MOUNT="pki_int_${SAFE_NAME}"
  #local CERT_NAME="Vault Intermediate CA - ${hostname}"
  local CERT_FILE
  CERT_FILE="$(fetch_cert "${PKI_MOUNT}" "${out_dir}")"

  case "$(uname -s)" in
  Darwin)
    install_macos_keychain "${CERT_FILE}"
    ;;
  Linux)
    print_nixos_instructions "${CERT_FILE}"
    ;;
  *)
    print_warning "Unrecognized OS, cert saved to ${CERT_FILE}"
    ;;
  esac
}

parse_args() {
  cluster=""
  out_dir="${DEFAULT_OUT_DIR}"

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

  if [[ -z "${cluster}" ]]; then
    local CLUSTERS
    mapfile -t CLUSTERS < <(list_clusters)
    cluster="$(select_cluster "${CLUSTERS[@]}")"
  fi

  local HOSTNAMES
  mapfile -t HOSTNAMES < <(fetch_hostnames "${cluster}")

  local hostname
  for hostname in "${HOSTNAMES[@]}"; do
    trust_hostname "${hostname}" "${out_dir}"
  done

  print_status "Finished trusting intermediate CA certs for cluster: ${cluster}. Restart your browser for changes to take effect."
}

main "$@"
