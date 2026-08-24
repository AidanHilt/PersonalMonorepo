#!/bin/bash

set -euo pipefail
nix build $PERSONAL_MONOREPO_LOCATION/nix/mono-flake#nixosConfigurations.iso-image-aarch64.config.system.build.isoImage
