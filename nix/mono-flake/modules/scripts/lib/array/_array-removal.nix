{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

_array-removal = pkgs.writeShellScriptBin "_array-removal" ''

remove_item_new_array() {
  local -n arr_ref=$1
  local item_to_remove=$2
  local new_array=()

  for item in "''${arr_ref[@]}"; do
    if [[ "$item" != "$item_to_remove" ]]; then
      new_array+=("$item")
    fi
  done

  arr_ref=("''${new_array[@]}")
}
'';
in

{
  environment.systemPackages = [
    _array-removal
  ];
}