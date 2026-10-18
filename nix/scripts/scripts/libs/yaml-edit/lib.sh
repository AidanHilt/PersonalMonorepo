#!/bin/bash
# Concatenated into writeShellApplication's run.sh, which applies
# set -euo pipefail; keep this safe under those options.

# yaml-edit-apply applies a yq expression to a file in place.
yaml-edit-apply() {
  local YQ_EXPR="$1"
  local FILE_NAME="$2"

  yq -P eval "$YQ_EXPR" -i "$FILE_NAME"
}

# yaml-edit-reorder rewrites FILE_NAME as:
#   HEADER_LITERAL (optional literal first line)
#   HEADER_EXPR evaluated against FILE_NAME (optional; "" to skip),
#     indented by two spaces when HEADER_INDENT is non-empty
#   two blank lines
#   REST_EXPR evaluated against FILE_NAME
# If STRIP_LITERAL is non-empty, any line exactly matching it is dropped
# from both the header and rest blocks (used to strip a literal header
# comment that a pick()-based header expression may itself echo back).
yaml-edit-reorder() {
  local FILE_NAME="$1"
  local HEADER_LITERAL="$2"
  local HEADER_EXPR="$3"
  local HEADER_INDENT="$4"
  local REST_EXPR="$5"
  local STRIP_LITERAL="$6"
  local TEMP_FILE

  TEMP_FILE="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$TEMP_FILE'" RETURN

  {
    if [[ -n "$HEADER_LITERAL" ]]; then
      echo "$HEADER_LITERAL"
    fi

    if [[ -n "$HEADER_EXPR" ]]; then
      local header_block
      header_block="$(yq eval "$HEADER_EXPR" "$FILE_NAME")"
      if [[ -n "$STRIP_LITERAL" ]]; then
        header_block="$(printf '%s\n' "$header_block" | sed "/^${STRIP_LITERAL}\$/d")"
      fi
      if [[ -n "$HEADER_INDENT" ]]; then
        header_block="$(printf '%s\n' "$header_block" | sed 's/^/  /')"
      fi
      printf '%s\n' "$header_block"
    fi

    echo ""
    echo ""

    local rest_block
    rest_block="$(yq eval "$REST_EXPR" "$FILE_NAME")"
    if [[ -n "$STRIP_LITERAL" ]]; then
      rest_block="$(printf '%s\n' "$rest_block" | sed "/^${STRIP_LITERAL}\$/d")"
    fi
    printf '%s\n' "$rest_block"
  } >"$TEMP_FILE"

  mv "$TEMP_FILE" "$FILE_NAME"
}
