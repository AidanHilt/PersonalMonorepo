{ inputs, globals, pkgs, machine-config, lib, ...}:

let
  _context-context-selector = pkgs.writeText "_context-contexts-selector" ''
    _context-context-selector() {
      if [[ -z "''${ATILS_CONTEXTS_DIRECTORY}" ]]; then
        echo "Error: ATILS_CONTEXTS_DIRECTORY environment variable is not set"
        echo "Please set it to your desired contexts directory path"
        exit 1
      fi

      if [[ -d "$ATILS_CONTEXTS_DIRECTORY" ]]; then
        contexts=($(ls -1 "$ATILS_CONTEXTS_DIRECTORY" 2>/dev/null))
        if [[ ''${#contexts[@]} -eq 0 ]]; then
          echo "No contexts found"
          return 1
        fi
        i=1
        for context in "''${contexts[@]}"; do
          echo "$i. $context"
          ((i++))
        done
      else
        echo "  (contexts directory does not exist)"
        return 1
      fi
    }
  '';
in

{
  environment.shellInit = "source ${_context-context-selector}";
}