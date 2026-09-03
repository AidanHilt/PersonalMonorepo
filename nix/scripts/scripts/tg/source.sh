#!/bin/bash

tg() {
  # If no args at all -> run terragrunt in current dir
  if [[ $# -eq 0 ]]; then
    terragrunt
    return
  fi

  local dir="$1"

  # If first arg looks like a directory, shift it off
  if [[ -n "$TG_WORKING_DIR" && -d "$TG_WORKING_DIR/$dir" ]]; then
    shift
    terragrunt --working-dir "$TG_WORKING_DIR/$dir" "$@"
  else
    # Fallback: just run terragrunt normally
    terragrunt "$@"
  fi
}
