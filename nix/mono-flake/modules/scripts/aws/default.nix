{ inputs, globals, pkgs, machine-config, lib, ...}:
{
 imports = [
   ./aws-assume-role.nix
 ];
}
