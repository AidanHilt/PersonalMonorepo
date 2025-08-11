{pkgs, ...}:

let
  context-selector = pkgs.writeText "context-selector.sh" ''
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
        echo -n "Select a context: "
        read CONTEXT_SELECTION
        if [[ -z "''${ZSH_VERSION-}" ]]; then
          CONTEXT_NAME=''${contexts[$CONTEXT_SELECTION - 1]}
        else
          CONTEXT_NAME=''${contexts[$CONTEXT_SELECTION]}
        fi
      else
        echo "  (contexts directory does not exist)"
        return 1
      fi
    }
  '';
in

{
  contextSelector = context-selector;
}