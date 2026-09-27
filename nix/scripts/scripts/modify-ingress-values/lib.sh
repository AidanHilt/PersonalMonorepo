#!/bin/bash

_modify-ingress-values() {
  local YQ_STRING="$1"
  local FILE_NAME="$2"

  eval "yq -P eval '$YQ_STRING' -i \"$FILE_NAME\""

  TEMP_HOSTNAMES="$(mktemp)"
  TEMP_REST="$(mktemp)"

  local TEMP_HOSTNAMES
  local TEMP_REST

  yq eval '.hostnames' "$FILE_NAME" >"$TEMP_HOSTNAMES"
  yq eval 'del(.hostnames) | to_entries | sort_by(.key) | from_entries' "$FILE_NAME" >"$TEMP_REST"

  {
    echo "hostnames:"
    sed 's/^/  /' "$TEMP_HOSTNAMES"
    echo ""
    echo ""
    cat "$TEMP_REST"
  } >"$FILE_NAME"

  rm "$TEMP_HOSTNAMES" "$TEMP_REST"
}
