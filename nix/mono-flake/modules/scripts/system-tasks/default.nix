{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ./system-tasks-generate-hashed-password.nix
  ];
}