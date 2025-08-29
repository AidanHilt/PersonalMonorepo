{ inputs, globals, pkgs, machine-config, lib, ...}:

let
contextSelector = import ./_context-context-selector.nix {inherit pkgs;};

context-populate-context = pkgs.writeShellScriptBin "context-populate-context" ''
#!/bin/bash

set -euo pipefail

source ${contextSelector.contextSelector}

show_usage() {
  echo "Usage: $0 --name <context_name> [--var-name value] [--another-var value2] ..."
  echo
  echo "Options:"
  echo "  --name       Context name (required)"
  echo "  --help, -h     Show this help message"
  echo
  echo "Additional arguments:"
  echo "  Any argument in the form --words-separated-by-dashes will be converted"
  echo "  to WORDS_SEPARATED_BY_DASHES and saved to this context's environment variables"
  echo
  echo "Examples:"
  echo "  $0 --name production --database-url 'postgres://...' --api-key 'secret123'"
  echo "  $0 --name dev --server-port 3000 --debug-mode true"
}

# Function to convert kebab-case to UPPER_SNAKE_CASE
kebab_to_upper_snake() {
  local kebab="$1"
  # Remove leading dashes, convert to uppercase, replace dashes with underscores
  echo "''${kebab#--}" | tr '[:lower:]' '[:upper:]' | tr '-' '_'
}

# Function to validate argument format
is_valid_arg_format() {
  local arg="$1"
  # Check if it starts with -- and contains only letters, numbers, and dashes
  [[ "$arg" =~ ^--[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*$ ]]
}

# Initialize variables
CONTEXT_NAME=""
declare -a ENV_VARS=()

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --name)
      if [[ -z "$2" || "$2" =~ ^-- ]]; then
        echo "Error: --name requires a value"
        exit 1
      fi
      CONTEXT_NAME="$2"
      shift 2
      ;;
    --help|-h)
      show_usage
      exit 0
      ;;
    --*)
      # Check if it's a valid custom argument format
      if is_valid_arg_format "$1"; then
        if [[ -z "$2" || "$2" =~ ^-- ]]; then
          echo "Error: $1 requires a value"
          exit 1
        fi
        # Convert to uppercase snake case and store
        var_name=$(kebab_to_upper_snake "$1")
        ENV_VARS+=("$var_name=$2")
        shift 2
      else
        echo "Error: Invalid argument format '$1'"
        echo "Arguments must be in the format --words-separated-by-dashes"
        exit 1
      fi
      ;;
    *)
      echo "Error: Unknown argument '$1'"
      show_usage
      exit 1
      ;;
  esac
done

# If no context name provided, prompt user
if [[ -z "$CONTEXT_NAME" ]]; then
  _context-context-selector
fi

# Check if context name is empty
if [[ -z "$CONTEXT_NAME" ]]; then
  echo "Error: Context name cannot be empty"
  exit 1
fi

# Make context name readonly
readonly CONTEXT_NAME

# Check if we have any environment variables to set
if [[ ''${#ENV_VARS[@]} -eq 0 ]]; then
  echo "Warning: No environment variables provided"
  echo "Usage: $0 --name $CONTEXT_NAME --some-var value --another-var value2"
  exit 0
fi

# Check if dotenvx is available
if ! command -v dotenvx &> /dev/null; then
  echo "Error: dotenvx command not found"
  exit 1
fi

# Set each environment variable using dotenvx
echo "Setting environment variables for context: $CONTEXT_NAME"

if [[ ! -f "''${ATILS_CONTEXTS_DIRECTORY}/''${CONTEXT_NAME}/.env" ]]; then
  touch "''${ATILS_CONTEXTS_DIRECTORY}/''${CONTEXT_NAME}/.env"
fi

for env_var in "''${ENV_VARS[@]}"; do
  var_name="''${env_var%=*}"
  var_value="''${env_var#*=}"

  echo "$var_value"

  dotenvx set "$var_name" "$var_value" -f "''${ATILS_CONTEXTS_DIRECTORY}/''${CONTEXT_NAME}/.env";
done

echo
echo "✓ All environment variables set successfully for context: $CONTEXT_NAME"
echo
echo "Variables set:"
for env_var in "''${ENV_VARS[@]}"; do
  var_name="''${env_var%=*}"
  echo "  - $var_name"
done
'';
in

{
  environment.systemPackages = [
    context-populate-context
  ];
}