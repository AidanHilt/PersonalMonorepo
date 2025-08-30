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
in

{
  environment.interactiveShellInit = ''
    source ${tg}
  '';

  environment.etc."zsh/completions/_tg".text = ''
  #compdef tg

  _tg_complete() {
    local -a reply
    local base_dir="$TG_WORKING_DIR"
    local cur="$words[CURRENT]"

    # Only complete first arg (the directory) *if TG_WORKING_DIR is set*
    if [[ -n "$base_dir" && $CURRENT -eq 2 ]]; then
      # Generate directories under base_dir
      reply=(''${base_dir}/''${cur}*(/))
      # Strip base_dir prefix
      reply=(''${reply#$base_dir/})
      compadd -a reply
    else
      # After the path, or if TG_WORKING_DIR not set, try terragrunt completion if available
      if whence -w _terragrunt_complete &>/dev/null; then
        _terragrunt_complete
      fi
    fi
  }
  '';
}