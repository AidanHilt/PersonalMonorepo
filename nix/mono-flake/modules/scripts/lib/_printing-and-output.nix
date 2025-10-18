{ pkgs, ... }:

let
  printing-and-output = pkgs.writeText "_printing-and-output" ''
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  NC='\033[0m' # No Color

  print_status() {
    if [[ ! -v ATILS_LOG_LEVEL ]]; then
      ATILS_LOG_LEVEL="INFO"
    fi

    if [[ $ATILS_LOG_LEVEL = "DEBUG" ]] || [[ $ATILS_LOG_LEVEL = "INFO" ]]; then
      echo -e "''${GREEN}[INFO]''${NC} $1"
    fi
  }

  print_warning() {
    if [[ ! -v ATILS_LOG_LEVEL ]]; then
      ATILS_LOG_LEVEL="INFO"
    fi

    if [[ $ATILS_LOG_LEVEL = "DEBUG" ]] || [[ $ATILS_LOG_LEVEL = "INFO" ]] || [[ $ATILS_LOG_LEVEL = "WARN" ]]; then
      echo -e "''${YELLOW}[WARN]''${NC} $1"
    fi
  }

  print_error() {
    echo -e "''${RED}[ERROR]''${NC} $1"
  }

  print_debug() {
    if [[ ! -v ATILS_LOG_LEVEL ]]; then
      ATILS_LOG_LEVEL="INFO"
    fi

    if [[ $ATILS_LOG_LEVEL = "DEBUG" ]]; then
      echo -e "''${BLUE}[DEBUG]''${NC} $1"
    fi
  }
  '';
in

{
  printing-and-output = printing-and-output;
}