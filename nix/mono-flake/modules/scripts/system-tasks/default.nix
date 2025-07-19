{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ./system-tasks-generate-hashed-password.nix
  ];
}