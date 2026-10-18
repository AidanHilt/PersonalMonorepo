#!/bin/bash
# Environment variable presence checks.
#
# Usage (from a run.sh that also declares "# @lib: env-checks" and
# "# @lib: printing-and-output"):
#
#   require_env PERSONAL_MONOREPO_LOCATION "Path to your personal monorepo"
#   require_monorepo

#shellcheck disable=SC2329
require_env() {
  local var_name="$1"
  local description="${2:-}"

  if [[ -z "${!var_name:-}" ]]; then
    if [[ -n "$description" ]]; then
      print_error "$var_name must be set: $description"
    else
      print_error "$var_name must be set"
    fi
    exit 1
  fi
}

#shellcheck disable=SC2329
require_monorepo() {
  require_env PERSONAL_MONOREPO_LOCATION "Path to your personal monorepo"
}
