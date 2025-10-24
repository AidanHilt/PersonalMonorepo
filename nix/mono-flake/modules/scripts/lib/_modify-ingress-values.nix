{ inputs, globals, pkgs, machine-config, lib, ... }:

let

  _modify-ingress-values = pkgs.writeText "_modify-ingress-values.sh" ''
    _modify-ingress-values() {
      local yq_string="$1"
      local filename="$2"

      yq eval "$yq_string" -i "$filename"

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
  environment.interactiveShellInit = ''
    source ${_modify-ingress-values}
  '';
}