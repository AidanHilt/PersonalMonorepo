{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

custom-images-build-image = pkgs.writeShellScriptBin "custom-images-build-image" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

IMAGE_NAME=""
IMAGE_TAG="latest"
BRANCH_BUILD=true

show_help () {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Build and publish one of the images in our custom-image flake"
  echo ""
  echo "OPTIONS:"
  echo "--image-name The name of the image to build. Must exist in the flake"
  echo "--image-tag The tag to use for the image. Defaults to the local personal monorepo branch"
  echo "--version-build Basically means we're doing a "real" build"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --image-name)
      IMAGE_NAME="$2"
      shift 2
      ;;
    --image-tag)
      IMAGE_TAG="$2"
      shift 2
      ;;
    --version-build)
      BRANCH_BUILD=false
      shift 1
      ;;
    --help)
      show_help
      exit 0
      ;;
    *)
      print_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

modify_and_load_image() {
  local IMAGE_PATH="$1"
  local ARCH="$2"
  local VAR_NAME="$3"
  local WORK_DIR="$TEMP_DIR/$ARCH"

  mkdir -p "$WORK_DIR"

  print_debug "Extracting $ARCH image..."
  tar -xf "$IMAGE_PATH" -C "$WORK_DIR" --no-same-permissions

  chmod -R 755 "$WORK_DIR"

  print_debug "Modifying $ARCH manifest..."
  jq --arg arch "$ARCH" '
    .[0].RepoTags = [
      .[0].RepoTags[0] |
      sub("^"; "aidanhilt/") |
      sub(":"; ":" + $arch + "-")
    ]
  ' "$WORK_DIR/manifest.json" > "$WORK_DIR/manifest.json.tmp"

  mv -f "$WORK_DIR/manifest.json.tmp" "$WORK_DIR/manifest.json"

  MODIFIED_IMAGE="$TEMP_DIR/modified.tar"
  tar -cf "$MODIFIED_IMAGE" -C "$WORK_DIR" .

  print_debug "Loading modified $ARCH image..."
  docker load < "$MODIFIED_IMAGE"

  local LOADED_TAG=$(jq -r '.[0].RepoTags[0]' "$WORK_DIR/manifest.json")
  eval "$VAR_NAME='$LOADED_TAG'"
}

if [[ -z "$IMAGE_NAME" ]]; then
  IMAGES_DIR="$PERSONAL_MONOREPO_LOCATION/nix/custom-images/images"

  if [[ ! -d "$IMAGES_DIR" ]]; then
    print_error "Images directory not found: $IMAGES_DIR"
    exit 1
  fi

  mapfile -t AVAILABLE_IMAGES < <(find "$IMAGES_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)

  if [[ ''${#AVAILABLE_IMAGES[@]} -eq 0 ]]; then
    print_error "No images found in $IMAGES_DIR"
    exit 1
  fi

  print_status "Available images:"
  for i in "''${!AVAILABLE_IMAGES[@]}"; do
    echo "  $((i + 1))) ''${AVAILABLE_IMAGES[$i]}"
  done

  read -p "Select an image (1-''${#AVAILABLE_IMAGES[@]}): " SELECTION

  if [[ ! "$SELECTION" =~ ^[0-9]+$ ]] || [[ "$SELECTION" -lt 1 ]] || [[ "$SELECTION" -gt ''${#AVAILABLE_IMAGES[@]} ]]; then
    print_error "Invalid selection"
    exit 1
  fi

  IMAGE_NAME="''${AVAILABLE_IMAGES[$((SELECTION - 1))]}"
fi

print_debug "Building image: $IMAGE_NAME"

FLAKE_DIR="$PERSONAL_MONOREPO_LOCATION/nix/custom-images"

print_debug "Building x86_64-linux image..."
X86_RESULT=$(nix build "$FLAKE_DIR#packages.x86_64-linux.$IMAGE_NAME" --print-out-paths --no-link)

print_debug "Building aarch64-linux image..."
AARCH64_RESULT=$(nix build "$FLAKE_DIR#packages.aarch64-linux.$IMAGE_NAME" --print-out-paths --no-link)

TEMP_DIR=$(mktemp -d)

modify_and_load_image "$X86_RESULT" "x86_64" X86_TAG
modify_and_load_image "$AARCH64_RESULT" "aarch64" AARCH64_TAG

CURRENT_BRANCH=$(git -C "$PERSONAL_MONOREPO_LOCATION" rev-parse --abbrev-ref HEAD)
SANITIZED_BRANCH="''${CURRENT_BRANCH//\//_}"

if [[ "$BRANCH_BUILD" = true ]]; then
  X86_TAG_NEW=$(echo "$X86_TAG" | sed "s/:.*/:x86_64-$SANITIZED_BRANCH/")
  AARCH64_TAG_NEW=$(echo "$AARCH64_TAG" | sed "s/:.*/:aarch64-$SANITIZED_BRANCH/")

  docker tag "$X86_TAG" "$X86_TAG_NEW"
  docker tag "$AARCH64_TAG" "$AARCH64_TAG_NEW"

  X86_TAG="$X86_TAG_NEW"
  AARCH64_TAG="$AARCH64_TAG_NEW"
fi

docker push "$X86_TAG"
docker push "$AARCH64_TAG"

MULTI_ARCH_TAG=$(echo "$X86_TAG" | sed 's/:x86_64-/:/')

print_debug "Creating multi-arch manifest..."
docker manifest rm "$MULTI_ARCH_TAG" 2>/dev/null || true
docker manifest create "$MULTI_ARCH_TAG" "$X86_TAG" "$AARCH64_TAG"

docker manifest push "$MULTI_ARCH_TAG"

print_debug "Creating latest tag"
if [[ "$BRANCH_BUILD" != true ]]; then
  MULTI_ARCH_TAG=$(echo "$MULTI_ARCH_TAG" | sed 's/\(.*\):.*/\1/')
  docker manifest rm "$MULTI_ARCH_TAG" 2>/dev/null || true
  docker manifest create "$MULTI_ARCH_TAG" "$X86_TAG" "$AARCH64_TAG"

  docker manifest push "$MULTI_ARCH_TAG"
fi

print_status "Multi-arch image $MULTI_ARCH_TAG created successfully!"
'';
in

{
  environment.systemPackages = [
    custom-images-build-image
  ];
}