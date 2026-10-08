#!/bin/bash
# Concatenated into writeShellApplication's run.sh, which applies
# set -euo pipefail; keep this safe under those options.

modify-master-stack-values() {
  local YQ_STRING="$1"
  local FILE_NAME="$2"
  local TEMP_HEADER
  local TEMP_REST

  eval "yq -P eval '$YQ_STRING' -i \"$FILE_NAME\""

  TEMP_HEADER=$(mktemp)
  TEMP_REST=$(mktemp)

  yq eval 'pick(["env", "hostnames", "defaultGitRepo", "gitRevision", "configuration"])' "$FILE_NAME" | sed '/^# Global config$/d' >"$TEMP_HEADER"
  yq eval 'del(.env) | del(.hostnames) | del(.defaultGitRepo) | del(.gitRevision) | del(.configuration) | to_entries | sort_by(.key) | from_entries' "$FILE_NAME" | sed '/^# Global config$/d' >"$TEMP_REST"

  {
    echo "# Global config"
    cat "$TEMP_HEADER"
    echo ""
    echo ""
    cat "$TEMP_REST"
  } >"$FILE_NAME"

  rm "$TEMP_HEADER" "$TEMP_REST"
}
