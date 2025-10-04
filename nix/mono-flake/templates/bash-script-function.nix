{ pkgs, ... }:

let

  $FUNCTION_NAME_BASE = pkgs.writeText "$FUNCTION_NAME_BASE.sh" ''
    $FUNCTION_NAME_BASE () {

    }
  '';
in

{
  $FUNCTION_NAME_BASE = $FUNCTION_NAME_BASE;
}