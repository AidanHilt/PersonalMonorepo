{ pkgs, ... }:

let

  _modify-master-stack-values = pkgs.writeText "_modify-master-stack-values.sh" ''
    _modify-master-stack-values () {
      local YQ_STRING="$1"
      local FILE_NAME="$2"

      eval "yq -P eval '$YQ_STRING' -i \"$FILE_NAME\""

      local TEMP_HEADER=$(mktemp)
      local TEMP_REST=$(mktemp)

      yq eval 'pick(["env", "hostnames", "defaultGitRepo", "gitRevision", "configuration"])' "$FILE_NAME" | sed '/^# Global config$/d' > "$TEMP_HEADER"
      yq eval 'del(.env) | del(.hostnames) | del(.defaultGitRepo) | del(.gitRevision) | del(.configuration) | to_entries | sort_by(.key) | from_entries' "$FILE_NAME" > "$TEMP_REST"

      {
        cat "$TEMP_HEADER"
        echo ""
        echo ""
        cat "$TEMP_REST"
      } > "$FILE_NAME"

      echo "$TEMP_HEADER"
      echo "$TEMP_REST"

      #rm "$TEMP_HEADER" "$TEMP_REST"
    }
  '';
in

{
  script = _modify-master-stack-values;
}