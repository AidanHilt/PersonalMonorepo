{ inputs, globals, pkgs, machine-config, lib, ...}:
{
 imports = [
  ./devterm.nix
  ./psql-manager.nix
  ./pvc-manager.nix
 ];
}
