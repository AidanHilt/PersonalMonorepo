{ pkgs, ... }:

let
  modify-ingress-values = pkgs.writeText "modify-ingress-values" ''
  _modify-ingress-values() {
    local yq_string="$1"
    local filename="$2"

    echo "This do make sense"

    eval "yq -P eval '$yq_string' -i \"$filename\""

    echo "This don't make sense"

    local TEMP_HOSTNAMES=$(mktemp)
    local TEMP_REST=$(mktemp)

    yq eval '.hostnames' "$filename" > "$TEMP_HOSTNAMES"
    yq eval 'del(.hostnames) | to_entries | sort_by(.key) | from_entries' "$filename" > "$TEMP_REST"

    {
      echo "hostnames:"
      sed 's/^/  /' "$TEMP_HOSTNAMES"
      echo ""
      echo ""
      cat "$TEMP_REST"
    } > "$filename"

    rm "$TEMP_HOSTNAMES" "$TEMP_REST"
    }
  '';
in

{
  modify-ingress-values = modify-ingress-values;
}