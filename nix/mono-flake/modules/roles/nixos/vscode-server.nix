# This ridiculous little number enables a compatability layer for the VSCode server used by the SSH remote plugin. Sorry.
{ inputs, globals, pkgs, machine-config, ...}:

{
 programs.nix-ld.enable = true;
}