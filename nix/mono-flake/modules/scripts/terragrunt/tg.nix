{ pkgs, ...}:

let
tg = pkgs.writeText "" ''
tg() {
  # If no args at all -> run terragrunt in current dir
  if [[ $# -eq 0 ]]; then
    terragrunt
    return
  fi

  local dir="$1"

  # If first arg looks like a directory, shift it off
  if [[ -n "$TG_WORKING_DIR" && -d "$TG_WORKING_DIR/$dir" ]]; then
    shift
    terragrunt --working-dir "$TG_WORKING_DIR/$dir" "$@"
  else
    # Fallback: just run terragrunt normally
    terragrunt "$@"
  fi
}
'';

tgAutoComplete = pkgs.writeText "" ''
  _tg_complete() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    local base_dir="$TG_WORKING_DIR"

    # Only complete first arg (the directory) *if TG_WORKING_DIR is set*
    if [[ -n "$base_dir" && $COMP_CWORD -eq 1 ]]; then
      COMPREPLY=($(compgen -d "$base_dir/$cur" | sed "s|$base_dir/||"))
    else
      # After the path, or if TG_WORKING_DIR not set, try terragrunt completion if available
      if declare -F _terragrunt_complete &>/dev/null; then
        _terragrunt_complete
      fi
    fi
  }
'';
in

{
  environment.interactiveShellInit = ''
    source ${tg}
    complete -F ${tgAutoComplete} tg
  '';
}