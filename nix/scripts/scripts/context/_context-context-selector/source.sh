#!/bin/zsh
# Sourced file is lint-checked as bash (see flake.nix sourceChecks).
# shellcheck shell=bash

_context-context-selector() {
  if [[ -z "${ATILS_CONTEXTS_DIRECTORY}" ]]; then
    echo "Error: ATILS_CONTEXTS_DIRECTORY environment variable is not set"
    echo "Please set it to your desired contexts directory path"
    exit 1
  fi

  if [[ -d "$ATILS_CONTEXTS_DIRECTORY" ]]; then
    # shellcheck disable=SC2207 # zsh-only: array assignment word-splits here; mapfile is unavailable in zsh
    contexts=($(ls -1 "$ATILS_CONTEXTS_DIRECTORY" 2>/dev/null))
    if [[ ${#contexts[@]} -eq 0 ]]; then
      echo "No contexts found"
      return 1
    fi
    i=1
    for context in "${contexts[@]}"; do
      echo "$i. $context"
      ((i++))
    done
    echo -n "Select a context: "
    read -r CONTEXT_SELECTION
    # shellcheck disable=SC2034 # CONTEXT_NAME is a global side effect consumed by the caller after sourcing
    if [[ -z "${ZSH_VERSION-}" ]]; then
      CONTEXT_NAME=${contexts[$CONTEXT_SELECTION - 1]}
    else
      CONTEXT_NAME=${contexts[$CONTEXT_SELECTION]}
    fi
  else
    echo "  (contexts directory does not exist)"
    return 1
  fi
}
