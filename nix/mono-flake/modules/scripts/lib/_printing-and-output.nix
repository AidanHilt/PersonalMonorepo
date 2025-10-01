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
    echo -e "''${GREEN}[INFO]''${NC} $1"
  }

  print_warning() {
    echo -e "''${YELLOW}[WARN]''${NC} $1"
  }

  print_error() {
    echo -e "''${RED}[ERROR]''${NC} $1"
  }

  print_debug() {
    echo -e "''${BLUE}[DEBUG]''${NC} $1"
  }
  '';
in

{
  printing-and-output = printing-and-output;
}