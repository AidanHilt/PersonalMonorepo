#!/bin/bash

# @lib: printing-and-output
# @lib: env-checks

set -euo pipefail

require_monorepo

nix build "$PERSONAL_MONOREPO_LOCATION/nix/mono-flake#nixosConfigurations.iso-image-x86_64.config.system.build.isoImage" -o "$PERSONAL_MONOREPO_LOCATION/result/iso-image-x86_64"
