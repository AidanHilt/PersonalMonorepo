#!/bin/bash

set -euo pipefail

if [[ ! -v VAULT_TOKEN ]]; then
  echo "VAULT_TOKEN not set, aborting"
  exit 1
fi

_copy-text-to-clipboard "$VAULT_TOKEN"
