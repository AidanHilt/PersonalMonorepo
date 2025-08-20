{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ./vault-initialize.nix
    ./vault-retrieve-token.nix
    ./vault-unseal.nix
  ];
}