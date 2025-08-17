{ inputs, globals, pkgs, machine-config, lib, ...}:

let
context-cd = pkgs.writeText "context-cd" ''
context-cd () {
  if [[ ! -v ATILS_CURRENT_CONTEXT ]]; then
    echo "No context is currently activated. Please activate one using 'context-activate-context'"
  else
    cd "$ATILS_CURRENT_CONTEXT_DIRECTORY"
  fi
}
'';
in

{
  environment.interactiveShellInit = ''
    source ${context-cd}
  '';
}