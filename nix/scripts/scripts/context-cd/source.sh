#!/bin/bash

context-cd() {
  if [[ ! -v ATILS_CURRENT_CONTEXT ]]; then
    echo "No context is currently activated. Please activate one using 'context-activate-context'"
  else
    cd "$ATILS_CURRENT_CONTEXT_DIR" || exit
  fi
}
