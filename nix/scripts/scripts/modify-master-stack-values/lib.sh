#!/bin/bash
# Concatenated into writeShellApplication's run.sh, which applies
# set -euo pipefail; keep this safe under those options.

modify-master-stack-values() {
  local YQ_STRING="$1"
  local FILE_NAME="$2"

  yaml-edit-apply "$YQ_STRING" "$FILE_NAME"
  yaml-edit-reorder "$FILE_NAME" "# Global config" \
    'pick(["env", "hostnames", "defaultGitRepo", "gitRevision", "configuration"])' "" \
    'del(.env) | del(.hostnames) | del(.defaultGitRepo) | del(.gitRevision) | del(.configuration) | to_entries | sort_by(.key) | from_entries' \
    "# Global config"
}
