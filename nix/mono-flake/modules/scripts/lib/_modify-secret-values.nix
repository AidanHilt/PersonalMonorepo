{ pkgs, ... }:

let

  _modify-secret-values = pkgs.writeText "_modify-secret-values.sh" ''
    _modify-secret-values () {
      local YQ_STRING="$1"
      local FILE_NAME="$2"

      eval "yq -P eval '$YQ_STRING | to_entries | sort_by(.key) | from_entries' -i \"$FILE_NAME\""
    }
  '';
in

{
  script = _modify-secret-values;
}