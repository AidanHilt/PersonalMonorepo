#!/bin/bash

# @lib: printing-and-output

set -euo pipefail

show_help() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Builds the devbox NixOS raw-efi image from the mono-flake and"
  echo "recreates the devbox Tart VM from it, with the home directory shared in."
  echo ""
  echo "OPTIONS:"
  echo "  --flake-path <path>      Path to the flake to build (default: \$PERSONAL_MONOREPO_LOCATION/nix/mono-flake)"
  echo "  --flake-attr <attr>      nixosConfigurations attribute to build (default: devbox)"
  echo "  --vm-name <name>         Name of the Tart VM (default: devbox)"
  echo "  --cpu-count <n>          Number of CPUs to allocate (default: 6)"
  echo "  --memory-mb <n>          Memory in MB to allocate (default: 10240)"
  echo "  --share-tag <tag>        Tag used for the virtiofs home directory share (default: home)"
  echo "  --share-path <path>      Host path to share as the home directory (default: \$HOME)"
  echo "  --boot-wait-seconds <n>  Seconds to wait for the VM to report running (default: 30)"
  echo "  --help, -h               Show this help message"
}

flake_path="${PERSONAL_MONOREPO_LOCATION}/nix/mono-flake"
flake_attr="devbox"
vm_name="devbox"
cpu_count="6"
memory_mb="10240"
share_tag="home"
share_path="${HOME}"
boot_wait_seconds="30"

while [[ $# -gt 0 ]]; do
  case $1 in
  --flake-path)
    flake_path=$2
    shift 2
    ;;
  --flake-attr)
    flake_attr=$2
    shift 2
    ;;
  --vm-name)
    vm_name=$2
    shift 2
    ;;
  --cpu-count)
    cpu_count=$2
    shift 2
    ;;
  --memory-mb)
    memory_mb=$2
    shift 2
    ;;
  --share-tag)
    share_tag=$2
    shift 2
    ;;
  --share-path)
    share_path=$2
    shift 2
    ;;
  --boot-wait-seconds)
    boot_wait_seconds=$2
    shift 2
    ;;
  --help | -h)
    show_help
    exit 0
    ;;
  *)
    print_error "Unknown option: $1"
    exit 1
    ;;
  esac
done

readonly FLAKE_PATH="${flake_path}"
readonly FLAKE_ATTR="${flake_attr}"
readonly VM_NAME="${vm_name}"
readonly CPU_COUNT="${cpu_count}"
readonly MEMORY_MB="${memory_mb}"
readonly SHARE_TAG="${share_tag}"
readonly SHARE_PATH="${share_path}"
readonly BOOT_WAIT_SECONDS="${boot_wait_seconds}"
readonly BUILD_ATTR="nixosConfigurations.${FLAKE_ATTR}.config.system.build.images.raw-efi"
readonly TART_VM_DISK="${HOME}/.tart/vms/${VM_NAME}/disk.img"

print_debug "Building flake attribute: ${BUILD_ATTR}"

build_out_path="$(nix build "${FLAKE_PATH}#${BUILD_ATTR}" --no-link --print-out-paths)"
readonly BUILD_OUT_PATH="${build_out_path}"

print_debug "Build output path: ${BUILD_OUT_PATH}"

image_file="$(find "${BUILD_OUT_PATH}" -maxdepth 2 -type f \( -name '*.raw' -o -name '*.img' \) -print -quit)"
readonly IMAGE_FILE="${image_file}"

if [[ -z "${IMAGE_FILE}" ]]; then
  print_error "Could not find a built .raw or .img file under ${BUILD_OUT_PATH}"
  exit 1
fi

print_debug "Found built image: ${IMAGE_FILE}"

if tart get "${VM_NAME}" >/dev/null 2>&1; then
  print_debug "Existing VM ${VM_NAME} found, deleting it for a clean rebuild"
  tart delete "${VM_NAME}"
fi

print_debug "Creating VM ${VM_NAME}"
tart create --linux "${VM_NAME}"

print_debug "Setting resources: ${CPU_COUNT} CPUs, ${MEMORY_MB}MB RAM"
tart set "${VM_NAME}" --cpu "${CPU_COUNT}" --memory "${MEMORY_MB}"

if [[ ! -f "${TART_VM_DISK}" ]]; then
  print_error "Expected Tart disk file not found at ${TART_VM_DISK}"
  exit 1
fi

# The disk's actual size comes from the built image itself (virtualisation.diskSize
# in the flake), not from any Tart CLI flag, since this overwrite replaces the
# placeholder disk entirely rather than resizing it.
print_debug "Swapping in built image at ${TART_VM_DISK}"
cp "${IMAGE_FILE}" "${TART_VM_DISK}"

print_debug "Starting VM ${VM_NAME} with home directory shared as tag ${SHARE_TAG}"
tart run "${VM_NAME}" --dir "${SHARE_PATH}:tag=${SHARE_TAG}" &

# Detach from the shell's job table so the VM keeps running after this script exits.
disown

waited_seconds="0"
until tart get "${VM_NAME}" --format json | grep -q '"Running": *true'; do
  if [[ "${waited_seconds}" -ge "${BOOT_WAIT_SECONDS}" ]]; then
    print_error "VM ${VM_NAME} did not report running within ${BOOT_WAIT_SECONDS} seconds"
    exit 1
  fi
  sleep 1
  waited_seconds=$((waited_seconds + 1))
done

print_status "VM ${VM_NAME} is running from image built at ${IMAGE_FILE}"
