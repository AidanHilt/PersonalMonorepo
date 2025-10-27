{ pkgs, ... }:

let
  modify-ingress-values = pkgs.writeText "modify-ingress-values" ''
    _modify-ingress-values() {
      local YQ_STRING="$1"
      local FILE_NAME="$2"

      eval "yq -P eval '$YQ_STRING' -i \"$FILE_NAME\""

      local TEMP_HOSTNAMES=$(mktemp)
      local TEMP_REST=$(mktemp)

      yq eval '.hostnames' "$FILE_NAME" > "$TEMP_HOSTNAMES"
      yq eval 'del(.hostnames) | to_entries | sort_by(.key) | from_entries' "$FILE_NAME" > "$TEMP_REST"

      {
        echo "hostnames:"
        sed 's/^/  /' "$TEMP_HOSTNAMES"
        echo ""
        echo ""
        cat "$TEMP_REST"
      } > "$FILE_NAME"

      rm "$TEMP_HOSTNAMES" "$TEMP_REST"
    }
  '';
in

{
  modify-ingress-values = modify-ingress-values;
}