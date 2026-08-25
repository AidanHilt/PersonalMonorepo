#!/bin/bash

set -euo pipefail

# @lib: printing-and-output

valid_run="false"

if [[ -v TG_WORKING_DIR ]]; then
  valid_run="true"
fi

if [[ "$valid_run" == "false" ]]; then
  print_error 'Please set TG_WORKING_DIR'
fi

terragrunt run apply --all --working-dir "$TG_WORKING_DIR/vault"
