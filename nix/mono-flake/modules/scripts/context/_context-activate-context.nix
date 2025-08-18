{ inputs, globals, pkgs, machine-config, lib, ...}:

let

  contextSelector = import ./_context-context-selector.nix {inherit pkgs;};

  activateContext = pkgs.writeText "activate-context.sh" ''
      context-activate-context () {
        CONTEXT_NAME=""

        while [[ $# -gt 0 ]]; do
          case $1 in
            --name|-n)
              CONTEXT_NAME="$2"
              shift 2
              ;;
            --help|-h)
              echo "Usage: $0 --context <context_name>"
              echo "     $0 -c <context_name>"
              echo
              echo "Options:"
              echo "  --name, -n  Name of the context to activate"
              echo "  --help, -h     Show this help message"
              echo
              exit 0
              ;;
            *)
              echo "Error: Unknown option $1"
              echo "Usage: $0 --context <context_name>"
              echo "     $0 -c <context_name>"
              echo
              echo "Options:"
              echo "  --name, -n  Name of the context to activate"
              echo "  --help, -h     Show this help message"
              echo
              exit 1
              ;;
          esac
        done

        if [[ -z "$CONTEXT_NAME" ]]; then
          _context-context-selector
        fi

        # Setting up variables related to the current context (i.e. define the current context and its location)
        export ATILS_CURRENT_CONTEXT="$CONTEXT_NAME"
        export ATILS_CURRENT_CONTEXT_DIR="$ATILS_CONTEXTS_DIRECTORY/$ATILS_CURRENT_CONTEXT"
        export ATILS_CURRENT_CONTEXT_SCRIPTS_DIR="$ATILS_CURRENT_CONTEXT_DIR/scripts"

        # Setting up PATH to include custom scripts
        export PATH="$ATILS_CURRENT_CONTEXT_SCRIPTS_DIR:$PATH"

        # Default values for terragrunt, can be overriden in the file
        export TG_WORKING_DIR="$PERSONAL_MONOREPO_LOCATION/terragrunt/$ATILS_CURRENT_CONTEXT"

        if [ -f "$ATILS_CONTEXTS_DIRECTORY/$CONTEXT_NAME/.env" ] && [ -s "$ATILS_CONTEXTS_DIRECTORY/$CONTEXT_NAME/.env" ]; then
          eval "$(dotenvx get -f "$ATILS_CONTEXTS_DIRECTORY/$CONTEXT_NAME/.env" | tr -d '}' | tr -d '{' | sed 's/:/=/g' | sed 's/,/\n/g' | sed 's/^/export /')"
        fi

        if [[ -v KUBECONFIG_CONTEXT ]]; then
          kubecm switch $KUBECONFIG_CONTEXT
        fi
      }
  '';
in

{
  environment.interactiveShellInit = ''
    source ${contextSelector.contextSelector}
    source ${activateContext}
  '';
}